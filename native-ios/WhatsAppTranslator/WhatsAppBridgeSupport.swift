import Foundation

struct WhatsAppPairingCodeResult: Equatable {
    let status: String
    let code: String?
}

enum WhatsAppBridgeResultParser {
    static let phoneLinkStatuses: Set<String> = [
        "phone-link-entry-not-found",
        "phone-link-entry-clicked",
    ]

    static let sessionStatuses: Set<String> = [
        "authenticated-ui-heuristic",
        "authentication-ui-heuristic",
        "unknown-ui",
    ]

    static func status(from result: Any?, allowed: Set<String>) -> String? {
        guard
            let values = result as? [String: Any],
            let status = values["status"] as? String,
            allowed.contains(status)
        else {
            return nil
        }

        return status
    }

    static func pairingCode(from result: Any?) -> WhatsAppPairingCodeResult? {
        guard
            let values = result as? [String: Any],
            let status = values["status"] as? String,
            status == "pairing-code-found" || status == "pairing-code-not-found"
        else {
            return nil
        }

        guard status == "pairing-code-found" else {
            return WhatsAppPairingCodeResult(status: status, code: nil)
        }

        guard
            let rawCode = values["code"] as? String,
            let normalizedCode = normalizePairingCode(rawCode)
        else {
            return nil
        }

        return WhatsAppPairingCodeResult(status: status, code: normalizedCode)
    }

    static func primitives(from result: Any?) -> BrowserPrimitiveStatus? {
        guard let values = result as? [String: Any] else {
            return nil
        }

        return BrowserPrimitiveStatus(
            indexedDB: boolValue(values["indexedDB"]),
            webSocket: boolValue(values["webSocket"]),
            cryptoSubtle: boolValue(values["cryptoSubtle"]),
            serviceWorker: boolValue(values["serviceWorker"])
        )
    }

    private static func normalizePairingCode(_ value: String) -> String? {
        let normalized = value
            .filter { $0.isLetter || $0.isNumber }
            .uppercased()

        guard normalized.count == 8, normalized.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return nil
        }

        return normalized
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

struct WhatsAppSessionResetValues: Equatable {
    let loadState: String
    let currentURL: String
    let javaScriptState: String
    let sessionState: String
    let pairingFlowState: String
    let pairingCode: String?
    let disconnectState: String
    let isLoading: Bool

    static let newLoad = WhatsAppSessionResetValues(
        loadState: "starting",
        currentURL: "not loaded",
        javaScriptState: "not evaluated",
        sessionState: "not evaluated",
        pairingFlowState: "not started",
        pairingCode: nil,
        disconnectState: "not requested",
        isLoading: true
    )

    static let disconnect = WhatsAppSessionResetValues(
        loadState: "not started",
        currentURL: "not loaded",
        javaScriptState: "not evaluated",
        sessionState: "not evaluated",
        pairingFlowState: "cleared",
        pairingCode: nil,
        disconnectState: "releasing WebKit session",
        isLoading: false
    )
}

enum WhatsAppDiagnosticsBuffer {
    static let defaultLimit = 20
    static let defaultMessageLimit = 500

    static func appending(
        _ message: String,
        to diagnostics: [String],
        limit: Int = defaultLimit,
        messageLimit: Int = defaultMessageLimit
    ) -> [String] {
        guard limit > 0, messageLimit > 0 else {
            return []
        }

        var updated = diagnostics
        updated.append(String(message.prefix(messageLimit)))

        if updated.count > limit {
            updated.removeFirst(updated.count - limit)
        }

        return updated
    }
}
