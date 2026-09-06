import Foundation

enum WhatsAppWebProfileIdentity {
    static let identifier = UUID(uuidString: "6F856F49-F202-4637-946A-75075B7A2A22")!
}

enum WhatsAppSessionPayloadStatus: Equatable {
    case value(String)
    case malformed
}

struct WhatsAppPairingCodeResult: Equatable {
    let status: String
    let code: String?
}

enum WhatsAppSessionInterpreter {
    static func status(from payload: Any?) -> WhatsAppSessionPayloadStatus {
        guard
            let values = payload as? [String: Any],
            let status = values["status"] as? String,
            !status.isEmpty
        else {
            return .malformed
        }
        return .value(status)
    }

    static func pairingCode(from payload: Any?) -> WhatsAppPairingCodeResult? {
        guard case let .value(status) = status(from: payload) else {
            return nil
        }

        guard status == "pairing-code-found" else {
            return WhatsAppPairingCodeResult(status: status, code: nil)
        }

        guard
            let values = payload as? [String: Any],
            let rawCode = values["code"] as? String,
            rawCode.range(
                of: #"^[A-Za-z0-9]{4}[\s-]?[A-Za-z0-9]{4}$"#,
                options: .regularExpression
            ) != nil
        else {
            return WhatsAppPairingCodeResult(status: status, code: nil)
        }

        let normalized = rawCode
            .filter { $0.isLetter || $0.isNumber }
            .uppercased()

        return WhatsAppPairingCodeResult(status: status, code: normalized)
    }
}

struct BoundedDiagnostics: Equatable {
    let limit: Int
    private(set) var messages: [String] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    mutating func append(_ message: String) {
        messages.append(message)
        if messages.count > limit {
            messages.removeFirst(messages.count - limit)
        }
    }
}
