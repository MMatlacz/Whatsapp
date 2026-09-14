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
    case invalidContent
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
                        durationMilliseconds: $0.durationMilliseconds, width: $0.width, height: $0.height,
                        isViewOnce: $0.isViewOnce)
              }, linkPreview: value.linkPreview.map {
                  .init(matchedText: $0.matchedText, canonicalURL: $0.canonicalURL,
                        title: $0.title, description: $0.description)
              }, content: transportContent(value.content),
              deliveryState: value.deliveryState.map(transportDeliveryState))
    }

    private static func transportContent(_ value: WhatsAppMessageContent) -> WhatsAppTransportMessageContent {
        switch value {
        case .text: return .init(kind: .text)
        case .media: return .init(kind: .media)
        case .linkPreview: return .init(kind: .linkPreview)
        case .location(let location):
            return .init(kind: .location, location: .init(
                latitude: location.latitude, longitude: location.longitude, name: location.name, address: location.address))
        case .contact(let cards):
            return .init(kind: .contact, contacts: cards.map { .init(displayName: $0.displayName, vCard: $0.vCard) })
        case .poll(let poll):
            return .init(kind: .poll, poll: .init(question: poll.question, options: poll.options))
        case .revoked: return .init(kind: .revoked)
        case .system(let system):
            return .init(kind: .system, system: .init(type: system.type, text: system.text))
        case .unsupported(let rawType):
            return .init(kind: .unsupported, rawType: rawType)
        }
    }

    private static func content(_ value: WhatsAppTransportMessageContent) throws -> WhatsAppMessageContent {
        switch value.kind {
        case .text: return .text
        case .media: return .media
        case .linkPreview: return .linkPreview
        case .revoked: return .revoked
        case .location:
            guard let location = value.location, location.latitude.isFinite, location.longitude.isFinite,
                  (-90...90).contains(location.latitude), (-180...180).contains(location.longitude),
                  (location.name?.count ?? 0) <= 512, (location.address?.count ?? 0) <= 1_024 else {
                throw WhatsAppDomainMappingError.invalidContent
            }
            return .location(.init(latitude: location.latitude, longitude: location.longitude,
                                   name: location.name, address: location.address))
        case .contact:
            guard let cards = value.contacts, !cards.isEmpty, cards.count <= 8,
                  cards.allSatisfy({ !$0.vCard.isEmpty && $0.vCard.count <= 4_096
                      && ($0.displayName?.count ?? 0) <= 256 }) else {
                throw WhatsAppDomainMappingError.invalidContent
            }
            return .contact(cards.map { .init(displayName: $0.displayName, vCard: $0.vCard) })
        case .poll:
            guard let poll = value.poll, !poll.question.isEmpty, poll.question.count <= 2_048,
                  !poll.options.isEmpty, poll.options.count <= 20,
                  poll.options.allSatisfy({ !$0.isEmpty && $0.count <= 512 }) else {
                throw WhatsAppDomainMappingError.invalidContent
            }
            return .poll(.init(question: poll.question, options: poll.options))
        case .system:
            guard let system = value.system, !system.type.isEmpty, system.type.count <= 128,
                  (system.text?.count ?? 0) <= 2_048 else {
                throw WhatsAppDomainMappingError.invalidContent
            }
            return .system(.init(type: system.type, text: system.text))
        case .unsupported:
            guard let rawType = value.rawType, !rawType.isEmpty, rawType.count <= 64 else {
                throw WhatsAppDomainMappingError.invalidContent
            }
            return .unsupported(rawType: rawType)
        }
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
            linkPreview: try value.linkPreview.map(linkPreview),
            content: try content(value.content),
            deliveryState: value.deliveryState.map(deliveryState),
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
            height: value.height,
            isViewOnce: value.isViewOnce
        ) else {
            throw WhatsAppDomainMappingError.invalidMedia
        }
        return media
    }

    private static func linkPreview(_ value: WhatsAppTransportLinkPreview) throws -> WhatsAppLinkPreview {
        guard let preview = WhatsAppLinkPreview(
            matchedText: value.matchedText, canonicalURL: value.canonicalURL,
            title: value.title, description: value.description
        ) else {
            throw WhatsAppDomainMappingError.invalidMedia
        }
        return preview
    }

    private static func deliveryState(_ value: WhatsAppTransportDeliveryState) -> WhatsAppDeliveryState {
        WhatsAppDeliveryState(rawValue: value.rawValue)!
    }

    private static func transportDeliveryState(_ value: WhatsAppDeliveryState) -> WhatsAppTransportDeliveryState {
        WhatsAppTransportDeliveryState(rawValue: value.rawValue)!
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
