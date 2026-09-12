import Foundation
import SwiftUI
import WebKit

@MainActor
struct WhatsAppWebProbeView: View {
    @StateObject private var session = WhatsAppSessionController()
    @State private var showingWebPage = false

    var body: some View {
        NavigationStack {
            List {
                Section("Persistent profile") {
                    sessionRow("Data store", value: session.dataStoreState)
                    sessionRow("Profile ID", value: session.profileIdentifier)
                    sessionRow("User agent", value: session.userAgentState)
                }

                Section("WhatsApp Web") {
                    Button(session.isLoading ? "Loading WhatsApp Web..." : "Load WhatsApp Web") {
                        session.loadWhatsAppWeb()
                        showingWebPage = true
                    }
                    .disabled(session.isLoading || session.isDisconnecting)

                    Button("Show WhatsApp Web") {
                        showingWebPage = true
                    }
                    .disabled(session.webView == nil || session.isDisconnecting)

                    sessionRow("Load state", value: session.loadState)
                    sessionRow("Current URL", value: session.currentURL)
                    sessionRow("Swift -> JavaScript", value: session.javaScriptState)
                    sessionRow("Session UI", value: session.sessionState)
                }

                Section("Phone-number linking") {
                    Button("Start phone-number linking") {
                        session.startPhoneNumberLinking()
                        showingWebPage = true
                    }
                    .disabled(session.isLoading || session.isDisconnecting)

                    Button("Read pairing code") {
                        session.refreshPairingCode()
                    }
                    .disabled(session.isLoading || session.isDisconnecting)

                    Button("Refresh session state") {
                        session.refreshSessionState()
                    }
                    .disabled(session.isLoading || session.isDisconnecting)

                    sessionRow("Pairing flow", value: session.pairingFlowState)

                    if let pairingCode = session.pairingCode {
                        LabeledContent("Pairing code") {
                            Text(pairingCode)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Text("The pairing code exists only in memory and is cleared when a new session starts or the profile is disconnected.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        sessionRow("Pairing code", value: "not captured")
                    }
                }

                Section("Browser primitives") {
                    sessionRow("indexedDB", value: session.primitives.indexedDB.displayValue)
                    sessionRow("WebSocket", value: session.primitives.webSocket.displayValue)
                    sessionRow("crypto.subtle", value: session.primitives.cryptoSubtle.displayValue)
                    sessionRow("serviceWorker", value: session.primitives.serviceWorker.displayValue)
                }

                Section("Disconnect") {
                    Button("Disconnect WhatsApp", role: .destructive) {
                        Task {
                            await session.disconnect()
                        }
                    }
                    .disabled(session.isDisconnecting)

                    sessionRow("Disconnect state", value: session.disconnectState)
                }

                Section("Diagnostics") {
                    if session.diagnostics.isEmpty {
                        Text("No navigation or JavaScript errors recorded in this run.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(session.diagnostics.enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Text("Open WhatsApp Web to complete linking directly on the page. The page uses the same dedicated persistent profile as these diagnostics. Session detection is a heuristic; real pairing, restart restoration, and offline sync remain physical-iPhone checks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("WhatsApp Web Session")
            .sheet(isPresented: $showingWebPage, onDismiss: session.refreshSessionState) {
                NavigationStack {
                    if let webView = session.webView {
                        WhatsAppWebPage(webView: webView)
                            .navigationTitle("WhatsApp Web")
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingWebPage = false }
                                }
                            }
                    }
                }
                .interactiveDismissDisabled()
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

// Reuse the controller's exact web view so presenting or dismissing the page
// never creates a second session or reloads an in-progress linking flow.
#if os(iOS)
private struct WhatsAppWebPage: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
private struct WhatsAppWebPage: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

enum WhatsAppWebProfile {
    static let identifier = WhatsAppSessionContract.profileIdentifier
    static let webURL = URL(string: "https://web.whatsapp.com")!
    static let desktopSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    @MainActor
    static func makeDataStore() -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: identifier)
    }

    @MainActor
    static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = makeDataStore()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = desktopSafariUserAgent
        return webView
    }
}

@MainActor
final class WhatsAppSessionController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var loadState = "not started"
    @Published private(set) var currentURL = "not loaded"
    @Published private(set) var javaScriptState = "not evaluated"
    @Published private(set) var sessionState = "not evaluated"
    @Published private(set) var pairingFlowState = "not started"
    @Published private(set) var pairingCode: String?
    @Published private(set) var disconnectState = "not requested"
    @Published private(set) var primitives = BrowserPrimitiveStatus()
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isDisconnecting = false

    let profileIdentifier = WhatsAppWebProfile.identifier.uuidString
    let userAgentState = "desktop Safari"
    let dataStoreState: String

    @Published private(set) var webView: WKWebView?
    private var startPairingAfterLoad = false

    override init() {
        let dataStore = WhatsAppWebProfile.makeDataStore()
        self.dataStoreState = dataStore.isPersistent ? "dedicated persistent profile" : "unexpected nonpersistent profile"
        super.init()
    }

    func loadWhatsAppWeb() {
        startPairingAfterLoad = false
        apply(reset: .newLoad)
        diagnostics = []
        primitives = BrowserPrimitiveStatus()
        beginWhatsAppLoad()
    }

    func startPhoneNumberLinking() {
        pairingCode = nil
        disconnectState = "not requested"

        guard let webView, loadState == "finished", webView.url != nil else {
            startPairingAfterLoad = true
            apply(reset: .newLoad)
            pairingFlowState = "waiting for WhatsApp Web"
            diagnostics = []
            primitives = BrowserPrimitiveStatus()
            beginWhatsAppLoad()
            return
        }

        evaluatePhoneLinkEntryPoint(in: webView)
    }

    func refreshPairingCode() {
        guard let webView else {
            pairingFlowState = "WhatsApp Web not loaded"
            return
        }

        let script = """
        (() => {
            const visible = (element) => {
                const style = globalThis.getComputedStyle(element);
                const rect = element.getBoundingClientRect();
                return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
            };

            const candidates = Array.from(document.querySelectorAll('code, span, div'))
                .filter(visible)
                .map((element) => (element.textContent || '').replace(/\\s+/g, ' ').trim())
                .filter((text) => text.length >= 8 && text.length <= 12);

            const exact = candidates.find((text) => /^[A-Z0-9]{4}[\\s-]?[A-Z0-9]{4}$/i.test(text));
            if (!exact) {
                return { status: 'pairing-code-not-found' };
            }

            return {
                status: 'pairing-code-found',
                code: exact.replace(/[\\s-]/g, '').toUpperCase()
            };
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }

            if let error {
                self.pairingCode = nil
                self.pairingFlowState = "pairing-code-read-failed"
                self.recordDiagnostic("Pairing-code probe failed: \(error.localizedDescription)")
                return
            }

            guard let parsed = WhatsAppBridgeResultParser.pairingCode(from: result) else {
                self.pairingCode = nil
                self.pairingFlowState = "pairing-code-unexpected-result"
                self.recordDiagnostic("Pairing-code probe returned an unexpected result type or invalid code.")
                return
            }

            self.pairingFlowState = parsed.status
            self.pairingCode = parsed.code
        }
    }

    func refreshSessionState() {
        guard let webView else {
            sessionState = "WhatsApp Web not loaded"
            return
        }

        let script = """
        (() => {
            const normalizedText = (element) => (element.innerText || element.textContent || element.getAttribute('aria-label') || '')
                .replace(/\\s+/g, ' ')
                .trim()
                .toLowerCase();
            const visible = (element) => {
                const style = globalThis.getComputedStyle(element);
                const rect = element.getBoundingClientRect();
                return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
            };

            const interactive = Array.from(document.querySelectorAll('button, [role="button"], a')).filter(visible);
            const hasPhoneLinkEntry = interactive.some((element) => {
                const text = normalizedText(element);
                return text.includes('link with phone number') || text.includes('link with a phone number')
                    || text.includes('log in with phone number');
            });

            const hasChatUI = Boolean(
                document.querySelector('[aria-label*="Chat list" i], [aria-label*="Chats" i], [role="grid"]')
            );

            if (hasChatUI) {
                return { status: 'authenticated-ui-heuristic' };
            }
            if (hasPhoneLinkEntry) {
                return { status: 'authentication-ui-heuristic' };
            }
            return { status: 'unknown-ui' };
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }

            if let error {
                self.sessionState = "session-state-read-failed"
                self.recordDiagnostic("Session-state probe failed: \(error.localizedDescription)")
                return
            }

            guard let status = WhatsAppBridgeResultParser.status(
                from: result,
                allowed: WhatsAppBridgeResultParser.sessionStatuses
            ) else {
                self.sessionState = "session-state-unexpected-result"
                self.recordDiagnostic("Session-state probe returned an unexpected or unknown status.")
                return
            }

            self.sessionState = status
        }
    }

    func disconnect() async {
        guard !isDisconnecting else { return }

        isDisconnecting = true
        startPairingAfterLoad = false
        apply(reset: .disconnect)
        primitives = BrowserPrimitiveStatus()
        releaseWebView()

        disconnectState = "removing dedicated profile"
        let removalResult = await WhatsAppProfileRemovalRetry.run {
            try await WKWebsiteDataStore.remove(forIdentifier: WhatsAppWebProfile.identifier)
        }

        if removalResult.succeeded {
            disconnectState = "profile removed"
            let attemptDescription = removalResult.attempts == 1
                ? ""
                : " after \(removalResult.attempts) attempts"
            recordDiagnostic("Dedicated WebKit profile removed\(attemptDescription). The next load will create a clean profile with the same stable identifier.")
        } else if let error = removalResult.error {
            disconnectState = "profile removal failed"
            recordDiagnostic("Dedicated WebKit profile removal failed: \(error.localizedDescription)")
        }

        isDisconnecting = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadState = "loading"
        updateCurrentURL(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadState = "content received"
        updateCurrentURL(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadState = "finished"
        isLoading = false
        updateCurrentURL(from: webView)
        runBrowserPrimitiveProbe(in: webView)
        refreshSessionState()

        if startPairingAfterLoad {
            startPairingAfterLoad = false
            evaluatePhoneLinkEntryPoint(in: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithNavigationError(prefix: "Navigation failed", webView: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithNavigationError(prefix: "Provisional navigation failed", webView: webView, error: error)
    }

    private func beginWhatsAppLoad() {
        let webView = ensureWebView()
        webView.load(URLRequest(url: WhatsAppWebProfile.webURL))
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let webView = WhatsAppWebProfile.makeWebView()
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func releaseWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    private func evaluatePhoneLinkEntryPoint(in webView: WKWebView) {
        pairingFlowState = "searching for phone-number linking"

        let script = """
        (() => {
            const normalizedText = (element) => (element.innerText || element.textContent || element.getAttribute('aria-label') || '')
                .replace(/\\s+/g, ' ')
                .trim()
                .toLowerCase();
            const visible = (element) => {
                const style = globalThis.getComputedStyle(element);
                const rect = element.getBoundingClientRect();
                return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
            };

            const candidates = Array.from(document.querySelectorAll('button, [role="button"], a')).filter(visible);
            const entry = candidates.find((element) => {
                const text = normalizedText(element);
                return text.includes('link with phone number') || text.includes('link with a phone number')
                    || text.includes('log in with phone number');
            });

            if (!entry) {
                return { status: 'phone-link-entry-not-found' };
            }

            entry.click();
            return { status: 'phone-link-entry-clicked' };
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }

            if let error {
                self.pairingFlowState = "phone-link-entry-probe-failed"
                self.recordDiagnostic("Phone-link entry probe failed: \(error.localizedDescription)")
                return
            }

            guard let status = WhatsAppBridgeResultParser.status(
                from: result,
                allowed: WhatsAppBridgeResultParser.phoneLinkStatuses
            ) else {
                self.pairingFlowState = "phone-link-entry-unexpected-result"
                self.recordDiagnostic("Phone-link entry probe returned an unexpected or unknown status.")
                return
            }

            self.pairingFlowState = status
        }
    }

    private func runBrowserPrimitiveProbe(in webView: WKWebView) {
        let script = """
        (() => ({
            indexedDB: typeof globalThis.indexedDB !== 'undefined',
            webSocket: typeof globalThis.WebSocket !== 'undefined',
            cryptoSubtle: Boolean(globalThis.crypto && globalThis.crypto.subtle),
            serviceWorker: Boolean(globalThis.navigator && 'serviceWorker' in globalThis.navigator)
        }))()
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }

            if let error {
                self.javaScriptState = "failed"
                self.recordDiagnostic("JavaScript probe failed: \(error.localizedDescription)")
                return
            }

            guard let primitives = WhatsAppBridgeResultParser.primitives(from: result) else {
                self.javaScriptState = "unexpected result"
                self.recordDiagnostic("JavaScript probe returned an unexpected result type.")
                return
            }

            self.javaScriptState = "success"
            self.primitives = primitives
        }
    }

    private func finishWithNavigationError(prefix: String, webView: WKWebView, error: Error) {
        loadState = "failed"
        isLoading = false
        startPairingAfterLoad = false
        updateCurrentURL(from: webView)
        recordDiagnostic("\(prefix): \(error.localizedDescription)")
    }

    private func updateCurrentURL(from webView: WKWebView) {
        currentURL = webView.url?.absoluteString ?? "not loaded"
    }

    private func apply(reset: WhatsAppSessionResetValues) {
        loadState = reset.loadState
        currentURL = reset.currentURL
        javaScriptState = reset.javaScriptState
        sessionState = reset.sessionState
        pairingFlowState = reset.pairingFlowState
        pairingCode = reset.pairingCode
        disconnectState = reset.disconnectState
        isLoading = reset.isLoading
    }

    private func recordDiagnostic(_ message: String) {
        diagnostics = WhatsAppDiagnosticsBuffer.appending(message, to: diagnostics)
    }
}
