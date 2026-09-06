import Foundation
import SwiftUI
import WebKit

@MainActor
struct WhatsAppWebProbeView: View {
    @StateObject private var probe = WhatsAppWebProbe()

    var body: some View {
        NavigationStack {
            List {
                Section("Persistent profile") {
                    probeRow("Data store", value: probe.dataStoreState)
                    probeRow("Profile ID", value: probe.profileIdentifier)
                    probeRow("User agent", value: probe.userAgentState)
                }

                Section("WhatsApp Web") {
                    Button(probe.isLoading ? "Loading WhatsApp Web..." : "Load WhatsApp Web") {
                        probe.loadWhatsAppWeb()
                    }
                    .disabled(probe.isLoading)

                    probeRow("Load state", value: probe.loadState)
                    probeRow("Current URL", value: probe.currentURL)
                    probeRow("Swift -> JavaScript", value: probe.javaScriptState)
                }

                Section("Browser primitives") {
                    probeRow("indexedDB", value: probe.primitives.indexedDB.displayValue)
                    probeRow("WebSocket", value: probe.primitives.webSocket.displayValue)
                    probeRow("crypto.subtle", value: probe.primitives.cryptoSubtle.displayValue)
                    probeRow("serviceWorker", value: probe.primitives.serviceWorker.displayValue)
                }

                Section("Diagnostics") {
                    if probe.diagnostics.isEmpty {
                        Text("No navigation or JavaScript errors recorded in this run.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(probe.diagnostics.enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Text("This probe is intentionally off-screen and only loads web.whatsapp.com after you tap the button. CI validates compilation only. Authentication, linked-device behavior, and the WebKit go/no-go decision remain physical-iPhone checks in P0.3.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("P0.3 WebKit Probe")
        }
    }

    @ViewBuilder
    private func probeRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

@MainActor
final class WhatsAppWebProbe: NSObject, ObservableObject, WKNavigationDelegate {
    private static let profileID = UUID(uuidString: "6F856F49-F202-4637-946A-75075B7A2A22")!
    private static let whatsAppWebURL = URL(string: "https://web.whatsapp.com")!
    private static let desktopSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private static let diagnosticsLimit = 20

    @Published private(set) var loadState = "not started"
    @Published private(set) var currentURL = "not loaded"
    @Published private(set) var javaScriptState = "not evaluated"
    @Published private(set) var primitives = BrowserPrimitiveStatus()
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var isLoading = false

    let profileIdentifier = profileID.uuidString
    let userAgentState = "desktop Safari"
    let dataStoreState: String

    private let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        let dataStore = WKWebsiteDataStore(forIdentifier: Self.profileID)
        configuration.websiteDataStore = dataStore

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.desktopSafariUserAgent

        self.webView = webView
        self.dataStoreState = dataStore.isPersistent ? "dedicated persistent profile" : "unexpected nonpersistent profile"

        super.init()
        webView.navigationDelegate = self
    }

    func loadWhatsAppWeb() {
        diagnostics = []
        primitives = BrowserPrimitiveStatus()
        javaScriptState = "not evaluated"
        loadState = "starting"
        currentURL = "not loaded"
        isLoading = true

        webView.load(URLRequest(url: Self.whatsAppWebURL))
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
        runBrowserPrimitiveProbe()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithNavigationError(prefix: "Navigation failed", webView: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithNavigationError(prefix: "Provisional navigation failed", webView: webView, error: error)
    }

    private func finishWithNavigationError(prefix: String, webView: WKWebView, error: Error) {
        loadState = "failed"
        isLoading = false
        updateCurrentURL(from: webView)
        recordDiagnostic("\(prefix): \(error.localizedDescription)")
    }

    private func runBrowserPrimitiveProbe() {
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

            guard let values = result as? [String: Any] else {
                self.javaScriptState = "unexpected result"
                self.recordDiagnostic("JavaScript probe returned an unexpected result type.")
                return
            }

            self.javaScriptState = "success"
            self.primitives = BrowserPrimitiveStatus(
                indexedDB: Self.boolValue(values["indexedDB"]),
                webSocket: Self.boolValue(values["webSocket"]),
                cryptoSubtle: Self.boolValue(values["cryptoSubtle"]),
                serviceWorker: Self.boolValue(values["serviceWorker"])
            )
        }
    }

    private func updateCurrentURL(from webView: WKWebView) {
        currentURL = webView.url?.absoluteString ?? "not loaded"
    }

    private func recordDiagnostic(_ message: String) {
        diagnostics.append(String(message.prefix(500)))
        if diagnostics.count > Self.diagnosticsLimit {
            diagnostics.removeFirst(diagnostics.count - Self.diagnosticsLimit)
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }
}

struct BrowserPrimitiveStatus {
    var indexedDB: Bool?
    var webSocket: Bool?
    var cryptoSubtle: Bool?
    var serviceWorker: Bool?

    init(
        indexedDB: Bool? = nil,
        webSocket: Bool? = nil,
        cryptoSubtle: Bool? = nil,
        serviceWorker: Bool? = nil
    ) {
        self.indexedDB = indexedDB
        self.webSocket = webSocket
        self.cryptoSubtle = cryptoSubtle
        self.serviceWorker = serviceWorker
    }
}

private extension Optional where Wrapped == Bool {
    var displayValue: String {
        switch self {
        case .some(true):
            return "available"
        case .some(false):
            return "unavailable"
        case .none:
            return "not evaluated"
        }
    }
}
