import Foundation

enum WhatsAppBridgeRequestKind: String, Codable, Equatable, Sendable {
    case connectionState
    case listChats
    case loadMessages
    case sendText
    case reply
}

struct WhatsAppBridgeRequestPayload: Codable, Equatable, Sendable {
    let chatID: String?
    let cursor: WhatsAppTransportMessageCursor?
    let limit: Int?
    let text: String?
    let messageID: String?

    init(
        chatID: String? = nil,
        cursor: WhatsAppTransportMessageCursor? = nil,
        limit: Int? = nil,
        text: String? = nil,
        messageID: String? = nil
    ) {
        self.chatID = chatID
        self.cursor = cursor
        self.limit = limit
        self.text = text
        self.messageID = messageID
    }
}

struct WhatsAppBridgeRequest: Codable, Equatable, Sendable {
    let version: Int
    let requestID: String
    let kind: WhatsAppBridgeRequestKind
    let payload: WhatsAppBridgeRequestPayload

    init(
        requestID: String = UUID().uuidString,
        kind: WhatsAppBridgeRequestKind,
        payload: WhatsAppBridgeRequestPayload = WhatsAppBridgeRequestPayload()
    ) {
        self.version = WhatsAppBridgeContract.version
        self.requestID = requestID
        self.kind = kind
        self.payload = payload
    }
}

enum WhatsAppBridgeWireMessage: Equatable, Sendable {
    case response(requestID: String, response: WhatsAppBridgeResponse)
    case event(WhatsAppTransportEvent)
    case failure(requestID: String?, code: String, message: String)
}

enum WhatsAppWebTransportError: Error, Equatable, Sendable {
    case invalidArgument(String)
    case malformedWireMessage(String)
    case unsupportedWireVersion(Int)
    case requestIDMismatch(expected: String, actual: String?)
    case bridgeFailure(code: String, message: String)
    case bridgeUnavailable(String)
    case requestTimedOut(String)
    case unexpectedWireMessage(String)
    case unexpectedResponse(expected: String, actual: String)
}

enum WhatsAppBridgeWireDecoder {
    static let version = 1

    static func decode(_ data: Data) throws -> WhatsAppBridgeWireMessage {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            throw WhatsAppWebTransportError.malformedWireMessage("root")
        }

        guard let wireVersion = dictionary["bridgeVersion"] as? Int else {
            throw WhatsAppWebTransportError.malformedWireMessage("bridgeVersion")
        }
        guard wireVersion == version else {
            throw WhatsAppWebTransportError.unsupportedWireVersion(wireVersion)
        }
        guard let type = dictionary["type"] as? String else {
            throw WhatsAppWebTransportError.malformedWireMessage("type")
        }

        switch type {
        case "response":
            let requestID = try requiredNonEmptyString(dictionary["requestID"], field: "requestID")
            let envelope = try envelopeData(from: dictionary["envelope"])
            return .response(
                requestID: requestID,
                response: try WhatsAppBridgeDecoder.decodeResponse(from: envelope)
            )
        case "event":
            let envelope = try envelopeData(from: dictionary["envelope"])
            return .event(try WhatsAppBridgeDecoder.decodeEvent(from: envelope))
        case "failure":
            let requestID = try optionalNonEmptyString(dictionary["requestID"], field: "requestID")
            let code = try requiredNonEmptyString(dictionary["code"], field: "code")
            let message = try requiredNonEmptyString(dictionary["message"], field: "message")
            return .failure(requestID: requestID, code: code, message: message)
        default:
            throw WhatsAppWebTransportError.malformedWireMessage("type:\(type)")
        }
    }

    private static func envelopeData(from value: Any?) throws -> Data {
        guard let value, JSONSerialization.isValidJSONObject(value) else {
            throw WhatsAppWebTransportError.malformedWireMessage("envelope")
        }
        do {
            return try JSONSerialization.data(withJSONObject: value)
        } catch {
            throw WhatsAppWebTransportError.malformedWireMessage("envelope")
        }
    }

    private static func requiredNonEmptyString(_ value: Any?, field: String) throws -> String {
        guard let value = value as? String, !value.isEmpty else {
            throw WhatsAppWebTransportError.malformedWireMessage(field)
        }
        return value
    }

    private static func optionalNonEmptyString(_ value: Any?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let string = value as? String, !string.isEmpty else {
            throw WhatsAppWebTransportError.malformedWireMessage(field)
        }
        return string
    }
}

protocol WhatsAppWebBridgeRuntime: Sendable {
    func connect() async throws
    func invoke(_ request: WhatsAppBridgeRequest) async throws -> Data
    func eventStream() async -> AsyncStream<Data>
}

actor WhatsAppWebTransport: WhatsAppTransport {
    private let runtime: any WhatsAppWebBridgeRuntime
    private let maximumPageSize = 100

    init(runtime: any WhatsAppWebBridgeRuntime) {
        self.runtime = runtime
    }

    func connect() async throws {
        try await runtime.connect()
    }

    func connectionState() async throws -> WhatsAppTransportConnectionState {
        let response = try await perform(kind: .connectionState)
        guard case .connectionState(let state) = response else {
            throw unexpected(expected: "connectionState", response: response)
        }
        return state
    }

    func listChats() async throws -> [WhatsAppTransportChat] {
        let response = try await perform(kind: .listChats)
        guard case .chats(let chats) = response else {
            throw unexpected(expected: "listChats", response: response)
        }
        return chats
    }

    func loadMessages(
        chatID: String,
        cursor: WhatsAppTransportMessageCursor?,
        limit: Int
    ) async throws -> WhatsAppTransportMessagePage {
        try requireIdentifier(chatID, field: "chatID")
        guard (1...maximumPageSize).contains(limit) else {
            throw WhatsAppWebTransportError.invalidArgument("limit")
        }

        let response = try await perform(
            kind: .loadMessages,
            payload: WhatsAppBridgeRequestPayload(chatID: chatID, cursor: cursor, limit: limit)
        )
        guard case .messages(let page) = response else {
            throw unexpected(expected: "loadMessages", response: response)
        }
        return page
    }

    func sendText(_ text: String, to chatID: String) async throws -> WhatsAppTransportMessage {
        try requireIdentifier(chatID, field: "chatID")
        try requireText(text)

        let response = try await perform(
            kind: .sendText,
            payload: WhatsAppBridgeRequestPayload(chatID: chatID, text: text)
        )
        guard case .sentMessage(let message) = response else {
            throw unexpected(expected: "sendText", response: response)
        }
        return message
    }

    func reply(
        _ text: String,
        to messageID: String,
        in chatID: String
    ) async throws -> WhatsAppTransportMessage {
        try requireIdentifier(messageID, field: "messageID")
        try requireIdentifier(chatID, field: "chatID")
        try requireText(text)

        let response = try await perform(
            kind: .reply,
            payload: WhatsAppBridgeRequestPayload(chatID: chatID, text: text, messageID: messageID)
        )
        guard case .repliedMessage(let message) = response else {
            throw unexpected(expected: "reply", response: response)
        }
        return message
    }

    func eventStream() async -> AsyncStream<WhatsAppTransportEvent> {
        let source = await runtime.eventStream()
        return AsyncStream { continuation in
            let task = Task {
                for await data in source {
                    guard !Task.isCancelled else { break }
                    guard
                        let decoded = try? WhatsAppBridgeWireDecoder.decode(data),
                        case .event(let event) = decoded
                    else {
                        continue
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func perform(
        kind: WhatsAppBridgeRequestKind,
        payload: WhatsAppBridgeRequestPayload = WhatsAppBridgeRequestPayload()
    ) async throws -> WhatsAppBridgeResponse {
        let request = WhatsAppBridgeRequest(kind: kind, payload: payload)
        let data = try await runtime.invoke(request)

        switch try WhatsAppBridgeWireDecoder.decode(data) {
        case .response(let requestID, let response):
            guard requestID == request.requestID else {
                throw WhatsAppWebTransportError.requestIDMismatch(
                    expected: request.requestID,
                    actual: requestID
                )
            }
            return response
        case .failure(let requestID, let code, let message):
            guard requestID == request.requestID else {
                throw WhatsAppWebTransportError.requestIDMismatch(
                    expected: request.requestID,
                    actual: requestID
                )
            }
            throw WhatsAppWebTransportError.bridgeFailure(code: code, message: message)
        case .event:
            throw WhatsAppWebTransportError.unexpectedWireMessage("event")
        }
    }

    private func requireIdentifier(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WhatsAppWebTransportError.invalidArgument(field)
        }
    }

    private func requireText(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WhatsAppWebTransportError.invalidArgument("text")
        }
    }

    private func unexpected(
        expected: String,
        response: WhatsAppBridgeResponse
    ) -> WhatsAppWebTransportError {
        .unexpectedResponse(expected: expected, actual: responseKind(response))
    }

    private func responseKind(_ response: WhatsAppBridgeResponse) -> String {
        switch response {
        case .connectionState: "connectionState"
        case .chats: "listChats"
        case .messages: "loadMessages"
        case .sentMessage: "sendText"
        case .repliedMessage: "reply"
        }
    }
}
