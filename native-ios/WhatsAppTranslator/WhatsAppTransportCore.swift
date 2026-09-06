import Foundation

enum WhatsAppTransportConnectionState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case syncing
    case ready
}

struct WhatsAppTransportChat: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let isGroup: Bool
    let unreadCount: Int
    let lastMessageTimestampMilliseconds: Int64?
}

struct WhatsAppTransportQuote: Codable, Equatable, Sendable {
    let messageID: String
    let senderID: String?
    let body: String?
}

enum WhatsAppTransportMediaKind: String, Codable, Equatable, Sendable {
    case image
    case video
    case audio
    case document
    case sticker
    case other
}

struct WhatsAppTransportMediaMetadata: Codable, Equatable, Sendable {
    let kind: WhatsAppTransportMediaKind
    let mimeType: String?
    let filename: String?
    let sizeBytes: Int64?
    let durationMilliseconds: Int64?
    let width: Int?
    let height: Int?
}

struct WhatsAppTransportMessage: Codable, Equatable, Sendable {
    let id: String
    let chatID: String
    let senderID: String?
    let timestampMilliseconds: Int64
    let body: String?
    let fromMe: Bool
    let quote: WhatsAppTransportQuote?
    let media: WhatsAppTransportMediaMetadata?
}

struct WhatsAppTransportMessageCursor: Codable, Equatable, Sendable {
    let beforeMessageID: String?
    let beforeTimestampMilliseconds: Int64?
}

struct WhatsAppTransportMessagePage: Codable, Equatable, Sendable {
    let messages: [WhatsAppTransportMessage]
    let nextCursor: WhatsAppTransportMessageCursor?
}

enum WhatsAppTransportEvent: Equatable, Sendable {
    case ready
    case message(WhatsAppTransportMessage)
    case messageUpdate(WhatsAppTransportMessage)
    case chatUpdate(WhatsAppTransportChat)
    case disconnected(reason: String?)
    case historySync(
        chatID: String,
        messages: [WhatsAppTransportMessage],
        nextCursor: WhatsAppTransportMessageCursor?
    )
}

protocol WhatsAppTransport: Sendable {
    func connect() async throws
    func connectionState() async throws -> WhatsAppTransportConnectionState
    func listChats() async throws -> [WhatsAppTransportChat]
    func loadMessages(
        chatID: String,
        cursor: WhatsAppTransportMessageCursor?,
        limit: Int
    ) async throws -> WhatsAppTransportMessagePage
    func sendText(_ text: String, to chatID: String) async throws -> WhatsAppTransportMessage
    func reply(
        _ text: String,
        to messageID: String,
        in chatID: String
    ) async throws -> WhatsAppTransportMessage
    func eventStream() async -> AsyncStream<WhatsAppTransportEvent>
}

enum WhatsAppBridgeResponse: Equatable, Sendable {
    case connectionState(WhatsAppTransportConnectionState)
    case chats([WhatsAppTransportChat])
    case messages(WhatsAppTransportMessagePage)
    case sentMessage(WhatsAppTransportMessage)
    case repliedMessage(WhatsAppTransportMessage)
}

enum WhatsAppBridgeDecodingError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case unknownEventKind(String)
    case unknownResponseKind(String)
    case invalidPayload(String)
}

enum WhatsAppBridgeContract {
    static let version = 1
}

enum WhatsAppBridgeDecoder {
    static func decodeEvent(from data: Data) throws -> WhatsAppTransportEvent {
        let header = try decodeHeader(from: data)
        try requireSupportedVersion(header.version)

        switch header.kind {
        case "ready":
            _ = try decodeEnvelope(EmptyPayload.self, from: data)
            return .ready
        case "message":
            let payload = try decodeEnvelope(WhatsAppTransportMessage.self, from: data).payload
            try validate(payload)
            return .message(payload)
        case "messageUpdate":
            let payload = try decodeEnvelope(WhatsAppTransportMessage.self, from: data).payload
            try validate(payload)
            return .messageUpdate(payload)
        case "chatUpdate":
            let payload = try decodeEnvelope(WhatsAppTransportChat.self, from: data).payload
            try validate(payload)
            return .chatUpdate(payload)
        case "disconnected":
            let payload = try decodeEnvelope(DisconnectedPayload.self, from: data).payload
            return .disconnected(reason: payload.reason)
        case "historySync":
            let payload = try decodeEnvelope(HistorySyncPayload.self, from: data).payload
            try validateHistorySync(payload)
            return .historySync(
                chatID: payload.chatID,
                messages: payload.messages,
                nextCursor: payload.nextCursor
            )
        default:
            throw WhatsAppBridgeDecodingError.unknownEventKind(header.kind)
        }
    }

    static func decodeResponse(from data: Data) throws -> WhatsAppBridgeResponse {
        let header = try decodeHeader(from: data)
        try requireSupportedVersion(header.version)

        switch header.kind {
        case "connectionState":
            let payload = try decodeEnvelope(ConnectionStatePayload.self, from: data).payload
            return .connectionState(payload.state)
        case "listChats":
            let payload = try decodeEnvelope(ChatListPayload.self, from: data).payload
            try payload.chats.forEach(validate)
            return .chats(payload.chats)
        case "loadMessages":
            let payload = try decodeEnvelope(WhatsAppTransportMessagePage.self, from: data).payload
            try validate(payload)
            return .messages(payload)
        case "sendText":
            let payload = try decodeEnvelope(MessagePayload.self, from: data).payload
            try validate(payload.message)
            return .sentMessage(payload.message)
        case "reply":
            let payload = try decodeEnvelope(MessagePayload.self, from: data).payload
            try validate(payload.message)
            return .repliedMessage(payload.message)
        default:
            throw WhatsAppBridgeDecodingError.unknownResponseKind(header.kind)
        }
    }

    private static func decodeHeader(from data: Data) throws -> EnvelopeHeader {
        do {
            return try JSONDecoder().decode(EnvelopeHeader.self, from: data)
        } catch {
            throw WhatsAppBridgeDecodingError.invalidPayload("envelope")
        }
    }

    private static func decodeEnvelope<Payload: Decodable>(
        _ payloadType: Payload.Type,
        from data: Data
    ) throws -> Envelope<Payload> {
        do {
            let envelope = try JSONDecoder().decode(Envelope<Payload>.self, from: data)
            guard envelope.version == WhatsAppBridgeContract.version else {
                throw WhatsAppBridgeDecodingError.unsupportedVersion(envelope.version)
            }
            return envelope
        } catch let error as WhatsAppBridgeDecodingError {
            throw error
        } catch {
            throw WhatsAppBridgeDecodingError.invalidPayload(String(describing: payloadType))
        }
    }

    private static func requireSupportedVersion(_ version: Int) throws {
        guard version == WhatsAppBridgeContract.version else {
            throw WhatsAppBridgeDecodingError.unsupportedVersion(version)
        }
    }

    private static func validate(_ chat: WhatsAppTransportChat) throws {
        guard !chat.id.isEmpty, chat.unreadCount >= 0 else {
            throw WhatsAppBridgeDecodingError.invalidPayload("chat")
        }
        if let timestamp = chat.lastMessageTimestampMilliseconds, timestamp < 0 {
            throw WhatsAppBridgeDecodingError.invalidPayload("chat")
        }
    }

    private static func validate(_ message: WhatsAppTransportMessage) throws {
        guard !message.id.isEmpty, !message.chatID.isEmpty, message.timestampMilliseconds >= 0 else {
            throw WhatsAppBridgeDecodingError.invalidPayload("message")
        }
        if let senderID = message.senderID, senderID.isEmpty {
            throw WhatsAppBridgeDecodingError.invalidPayload("message")
        }
        if let quote = message.quote {
            guard !quote.messageID.isEmpty else {
                throw WhatsAppBridgeDecodingError.invalidPayload("quote")
            }
            if let senderID = quote.senderID, senderID.isEmpty {
                throw WhatsAppBridgeDecodingError.invalidPayload("quote")
            }
        }
        if let media = message.media {
            try validate(media)
        }
    }

    private static func validate(_ media: WhatsAppTransportMediaMetadata) throws {
        let values: [Int64?] = [media.sizeBytes, media.durationMilliseconds]
        guard values.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
            throw WhatsAppBridgeDecodingError.invalidPayload("media")
        }
        let dimensions: [Int?] = [media.width, media.height]
        guard dimensions.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
            throw WhatsAppBridgeDecodingError.invalidPayload("media")
        }
    }

    private static func validate(_ cursor: WhatsAppTransportMessageCursor) throws {
        guard cursor.beforeMessageID != nil || cursor.beforeTimestampMilliseconds != nil else {
            throw WhatsAppBridgeDecodingError.invalidPayload("cursor")
        }
        if let messageID = cursor.beforeMessageID, messageID.isEmpty {
            throw WhatsAppBridgeDecodingError.invalidPayload("cursor")
        }
        if let timestamp = cursor.beforeTimestampMilliseconds, timestamp < 0 {
            throw WhatsAppBridgeDecodingError.invalidPayload("cursor")
        }
    }

    private static func validate(_ page: WhatsAppTransportMessagePage) throws {
        try page.messages.forEach(validate)
        if let nextCursor = page.nextCursor {
            try validate(nextCursor)
        }
    }

    private static func validateHistorySync(_ payload: HistorySyncPayload) throws {
        guard !payload.chatID.isEmpty else {
            throw WhatsAppBridgeDecodingError.invalidPayload("historySync")
        }
        try payload.messages.forEach { message in
            try validate(message)
            guard message.chatID == payload.chatID else {
                throw WhatsAppBridgeDecodingError.invalidPayload("historySync")
            }
        }
        if let nextCursor = payload.nextCursor {
            try validate(nextCursor)
        }
    }
}

private struct EnvelopeHeader: Decodable {
    let version: Int
    let kind: String
}

private struct Envelope<Payload: Decodable>: Decodable {
    let version: Int
    let kind: String
    let payload: Payload
}

private struct EmptyPayload: Decodable {}

private struct DisconnectedPayload: Decodable {
    let reason: String?
}

private struct HistorySyncPayload: Decodable {
    let chatID: String
    let messages: [WhatsAppTransportMessage]
    let nextCursor: WhatsAppTransportMessageCursor?
}

private struct ConnectionStatePayload: Decodable {
    let state: WhatsAppTransportConnectionState
}

private struct ChatListPayload: Decodable {
    let chats: [WhatsAppTransportChat]
}

private struct MessagePayload: Decodable {
    let message: WhatsAppTransportMessage
}
