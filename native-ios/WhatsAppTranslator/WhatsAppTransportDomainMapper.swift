import Foundation

#if SWIFT_PACKAGE
import WhatsAppDomainCore
#endif

enum WhatsAppDomainMappingError: Error, Equatable, Sendable {
    case invalidChatID(String)
    case invalidMessageID(String)
    case invalidParticipantID(String)
    case invalidTimestamp(Int64)
    case invalidChat
    case invalidMedia
    case invalidCursor
}

enum WhatsAppTransportDomainMapper {
    static func transportChat(_ value: WhatsAppChat) -> WhatsAppTransportChat {
        .init(id: value.id.rawValue, title: value.title, isGroup: value.kind == .group,
              unreadCount: value.unreadCount,
              lastMessageTimestampMilliseconds: value.lastMessageAt?.millisecondsSince1970)
    }

    static func transportMessage(_ value: WhatsAppMessage) -> WhatsAppTransportMessage {
        .init(id: value.id.rawValue, chatID: value.chatID.rawValue,
              senderID: value.senderID?.rawValue,
              timestampMilliseconds: value.timestamp.millisecondsSince1970,
              body: value.body, fromMe: value.fromMe,
              quote: value.quote.map {
                  .init(messageID: $0.messageID.rawValue, senderID: $0.senderID?.rawValue, body: $0.body)
              }, media: value.media.map {
                  .init(kind: transportMediaKind($0.kind), mimeType: $0.mimeType,
                        filename: $0.filename, sizeBytes: $0.sizeBytes,
                        durationMilliseconds: $0.durationMilliseconds, width: $0.width, height: $0.height)
              })
    }

    private static func transportMediaKind(_ value: WhatsAppMediaKind) -> WhatsAppTransportMediaKind {
        switch value {
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .document: .document
        case .sticker: .sticker
        case .other: .other
        }
    }

    static func chat(_ value: WhatsAppTransportChat) throws -> WhatsAppChat {
        let id = try chatID(value.id)
        let timestamp = try value.lastMessageTimestampMilliseconds.map(timestamp)
        guard let chat = WhatsAppChat(
            id: id,
            title: value.title,
            kind: value.isGroup ? .group : .direct,
            unreadCount: value.unreadCount,
            lastMessageAt: timestamp
        ) else {
            throw WhatsAppDomainMappingError.invalidChat
        }
        return chat
    }

    static func message(_ value: WhatsAppTransportMessage) throws -> WhatsAppMessage {
        WhatsAppMessage(
            id: try messageID(value.id),
            chatID: try chatID(value.chatID),
            senderID: try value.senderID.map(participantID),
            timestamp: try timestamp(value.timestampMilliseconds),
            body: value.body,
            fromMe: value.fromMe,
            quote: try value.quote.map(quote),
            media: try value.media.map(media),
            translation: nil
        )
    }

    static func cursor(_ value: WhatsAppTransportMessageCursor) throws -> WhatsAppMessageCursor {
        let messageID = try value.beforeMessageID.map(messageID)
        let timestamp = try value.beforeTimestampMilliseconds.map(timestamp)
        guard let cursor = WhatsAppMessageCursor(
            beforeMessageID: messageID,
            beforeTimestamp: timestamp
        ) else {
            throw WhatsAppDomainMappingError.invalidCursor
        }
        return cursor
    }

    static func page(_ value: WhatsAppTransportMessagePage) throws -> WhatsAppMessagePage {
        WhatsAppMessagePage(
            messages: try value.messages.map(message),
            nextCursor: try value.nextCursor.map(cursor)
        )
    }

    static func transportCursor(_ value: WhatsAppMessageCursor?) -> WhatsAppTransportMessageCursor? {
        value.map {
            WhatsAppTransportMessageCursor(
                beforeMessageID: $0.beforeMessageID?.rawValue,
                beforeTimestampMilliseconds: $0.beforeTimestamp?.millisecondsSince1970
            )
        }
    }

    private static func quote(_ value: WhatsAppTransportQuote) throws -> WhatsAppQuote {
        WhatsAppQuote(
            messageID: try messageID(value.messageID),
            senderID: try value.senderID.map(participantID),
            body: value.body
        )
    }

    private static func media(_ value: WhatsAppTransportMediaMetadata) throws -> WhatsAppMediaMetadata {
        guard let media = WhatsAppMediaMetadata(
            kind: mediaKind(value.kind),
            mimeType: value.mimeType,
            filename: value.filename,
            sizeBytes: value.sizeBytes,
            durationMilliseconds: value.durationMilliseconds,
            width: value.width,
            height: value.height
        ) else {
            throw WhatsAppDomainMappingError.invalidMedia
        }
        return media
    }

    private static func mediaKind(_ value: WhatsAppTransportMediaKind) -> WhatsAppMediaKind {
        switch value {
        case .image:
            .image
        case .video:
            .video
        case .audio:
            .audio
        case .document:
            .document
        case .sticker:
            .sticker
        case .other:
            .other
        }
    }

    private static func chatID(_ value: String) throws -> WhatsAppChatID {
        guard let id = WhatsAppChatID(value) else {
            throw WhatsAppDomainMappingError.invalidChatID(value)
        }
        return id
    }

    private static func messageID(_ value: String) throws -> WhatsAppMessageID {
        guard let id = WhatsAppMessageID(value) else {
            throw WhatsAppDomainMappingError.invalidMessageID(value)
        }
        return id
    }

    private static func participantID(_ value: String) throws -> WhatsAppParticipantID {
        guard let id = WhatsAppParticipantID(value) else {
            throw WhatsAppDomainMappingError.invalidParticipantID(value)
        }
        return id
    }

    private static func timestamp(_ value: Int64) throws -> WhatsAppTimestamp {
        guard let timestamp = WhatsAppTimestamp(millisecondsSince1970: value) else {
            throw WhatsAppDomainMappingError.invalidTimestamp(value)
        }
        return timestamp
    }
}
