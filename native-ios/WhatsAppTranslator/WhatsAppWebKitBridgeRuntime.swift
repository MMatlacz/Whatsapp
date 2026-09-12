import Foundation
import WebKit

@MainActor
final class WhatsAppWebKitBridgeRuntime: NSObject, WhatsAppWebBridgeRuntime, WKNavigationDelegate, WKScriptMessageHandler {
    private static let messageHandlerName = "whatsAppBridge"
    private static let requestTimeout: Duration = .seconds(15)

    private let events: AsyncStream<Data>
    private let eventContinuation: AsyncStream<Data>.Continuation
    private var webView: WKWebView?
    private var bridgeReady = false
    private var navigationInProgress = false
    private var navigationGeneration = UUID()
    private var connectWaiters: [CheckedContinuation<Void, Error>] = []
    private var pendingRequests: [String: CheckedContinuation<Data, Error>] = [:]

    override init() {
        var continuation: AsyncStream<Data>.Continuation!
        self.events = AsyncStream<Data> { continuation = $0 }
        self.eventContinuation = continuation
        super.init()
    }

    func connect() async throws {
        if bridgeReady { return }
        let webView = try ensureWebView()

        try await withCheckedThrowingContinuation { continuation in
            connectWaiters.append(continuation)
            guard !navigationInProgress else { return }
            navigationInProgress = true
            let generation = UUID()
            navigationGeneration = generation
            webView.load(URLRequest(url: WhatsAppWebProfile.webURL))
            Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .seconds(45))
                guard let self, self.webView === webView,
                      self.navigationGeneration == generation, !self.bridgeReady else { return }
                self.handleNavigationFailure()
            }
        }
    }

    func invoke(_ request: WhatsAppBridgeRequest) async throws -> Data {
        guard bridgeReady, let webView else {
            throw WhatsAppWebTransportError.bridgeUnavailable("page-not-ready")
        }

        let encoded = try JSONEncoder().encode(request)
        guard let requestJSON = String(data: encoded, encoding: .utf8) else {
            throw WhatsAppWebTransportError.bridgeUnavailable("request-encoding-failed")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[request.requestID] = continuation

            let script = """
            (() => {
                const bridge = globalThis.__waTranslatorBridge;
                if (!bridge || bridge.version !== \(WhatsAppBridgeWireDecoder.version) || typeof bridge.invoke !== 'function') {
                    return false;
                }
                return bridge.invoke(\(requestJSON));
            })()
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else { return }
                if error != nil {
                    self.failPendingRequest(
                        request.requestID,
                        error: WhatsAppWebTransportError.bridgeUnavailable("javascript-invocation-failed")
                    )
                    return
                }
                guard result as? Bool == true else {
                    self.failPendingRequest(
                        request.requestID,
                        error: WhatsAppWebTransportError.bridgeUnavailable("bridge-rejected-request")
                    )
                    return
                }
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.requestTimeout)
                self?.failPendingRequest(
                    request.requestID,
                    error: WhatsAppWebTransportError.requestTimedOut(request.requestID)
                )
            }
        }
    }

    func eventStream() async -> AsyncStream<Data> {
        events
    }

    /// Pairing material is deliberately separate from bridge events and storage.
    func connectionDiagnostic() async -> String {
        guard let webView, bridgeReady else { return "Page bridge is not ready." }
        let script = """
            (() => {
                const w = globalThis.WPP;
                return [Boolean(w?.isReady), Boolean(w?.conn?.isRegistered()),
                    Boolean(w?.conn?.isAuthenticated()), Boolean(w?.conn?.isMainReady()),
                    Boolean(w?.conn?.isOnline()), navigator.onLine];
            })()
            """
        guard let values = try? await webView.evaluateJavaScript(script) as? [Bool], values.count == 6 else {
            return "Runtime status could not be read."
        }
        let labels = ["Runtime", "Registered", "Authenticated", "Main ready", "Online", "Network"]
        return zip(labels, values).map { "\($0): \($1 ? "yes" : "no")" }.joined(separator: " · ")
    }

    func pairingCode() async throws -> String? {
        try await connect()
        guard let webView, webView.url?.host == "web.whatsapp.com" else {
            throw WhatsAppWebTransportError.bridgeUnavailable("pairing-unavailable")
        }
        let value = try await webView.callAsyncJavaScript("""
            if (!globalThis.WPP?.isReady || WPP.conn.isAuthenticated()) return null;
            const code = await WPP.conn.getAuthCode();
            return typeof code?.fullCode === 'string' ? code.fullCode : null;
            """, arguments: [:], in: nil, contentWorld: .page)
        guard let code = value as? String, !code.isEmpty, code.utf8.count < 8192 else { return nil }
        return code
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              url.scheme == "https", url.host == "web.whatsapp.com" else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        bridgeReady = false
        navigationInProgress = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationInProgress = false
        verifyInjectedBridge(in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleNavigationFailure()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == Self.messageHandlerName,
            message.frameInfo.isMainFrame,
            message.frameInfo.securityOrigin.protocol == "https",
            message.frameInfo.securityOrigin.host == "web.whatsapp.com",
            let string = message.body as? String,
            let data = string.data(using: .utf8)
        else {
            return
        }

        guard let decoded = try? WhatsAppBridgeWireDecoder.decode(data) else {
            return
        }

        switch decoded {
        case .response(let requestID, _):
            completePendingRequest(requestID, data: data)
        case .failure(let requestID, _, _):
            if let requestID {
                completePendingRequest(requestID, data: data)
            }
        case .event:
            eventContinuation.yield(data)
        }
    }

    func ensureWebView() throws -> WKWebView {
        if let webView { return webView }

        guard
            let scriptURL = Bundle.main.url(forResource: "WhatsAppBridge", withExtension: "js"),
            let bridgeSource = try? String(contentsOf: scriptURL, encoding: .utf8),
            let runtimeURL = Bundle.main.url(forResource: "WhatsAppRuntime", withExtension: "js", subdirectory: "generated"),
            let runtimeSource = try? String(contentsOf: runtimeURL, encoding: .utf8)
        else {
            throw WhatsAppWebTransportError.bridgeUnavailable("bridge-resource-missing")
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WhatsAppWebProfile.makeDataStore()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.userContentController.addUserScript(
            WKUserScript(source: runtimeSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: bridgeSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(self, name: Self.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WhatsAppWebProfile.desktopSafariUserAgent
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func verifyInjectedBridge(in webView: WKWebView) {
        let script = """
        Boolean(
            globalThis.__waTranslatorBridge &&
            globalThis.__waTranslatorBridge.version === \(WhatsAppBridgeWireDecoder.version) &&
            typeof globalThis.__waTranslatorBridge.invoke === 'function'
        )
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            guard error == nil, result as? Bool == true else {
                self.bridgeReady = false
                self.failConnectWaiters(
                    with: WhatsAppWebTransportError.bridgeUnavailable("bridge-not-installed")
                )
                return
            }

            self.bridgeReady = true
            self.resumeConnectWaiters()
        }
    }

    private func handleNavigationFailure() {
        navigationGeneration = UUID()
        navigationInProgress = false
        bridgeReady = false
        let error = WhatsAppWebTransportError.bridgeUnavailable("navigation-failed")
        failConnectWaiters(with: error)
        failAllPendingRequests(with: error)
        emitDisconnectedEvent(reason: "web-navigation-failed")
    }

    private func completePendingRequest(_ requestID: String, data: Data) {
        guard let continuation = pendingRequests.removeValue(forKey: requestID) else { return }
        continuation.resume(returning: data)
    }

    private func failPendingRequest(_ requestID: String, error: Error) {
        guard let continuation = pendingRequests.removeValue(forKey: requestID) else { return }
        continuation.resume(throwing: error)
    }

    private func failAllPendingRequests(with error: Error) {
        let continuations = pendingRequests.values
        pendingRequests.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private func resumeConnectWaiters() {
        let waiters = connectWaiters
        connectWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func failConnectWaiters(with error: Error) {
        let waiters = connectWaiters
        connectWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func emitDisconnectedEvent(reason: String) {
        let object: [String: Any] = [
            "bridgeVersion": WhatsAppBridgeWireDecoder.version,
            "type": "event",
            "envelope": [
                "version": WhatsAppBridgeContract.version,
                "kind": "disconnected",
                "payload": ["reason": reason]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        eventContinuation.yield(data)
    }
}

@MainActor
enum WhatsAppTransportFactory {
    static func makeWebKitTransport() -> WhatsAppWebTransport {
        WhatsAppWebTransport(runtime: WhatsAppWebKitBridgeRuntime())
    }
}
