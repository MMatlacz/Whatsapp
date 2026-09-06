import Foundation

public struct WhatsAppChatID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

public struct WhatsAppMessageID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

public struct WhatsAppParticipantID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

public struct WhatsAppTimestamp: Equatable, Hashable, Sendable, Comparable {
    public let millisecondsSince1970: Int64

    public init?(millisecondsSince1970: Int64) {
        guard millisecondsSince1970 >= 0 else {
            return nil
        }
        self.millisecondsSince1970 = millisecondsSince1970
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(millisecondsSince1970) / 1_000)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.millisecondsSince1970 < rhs.millisecondsSince1970
    }
}

public enum WhatsAppChatKind: Equatable, Sendable {
    case direct
    case group
}

public struct WhatsAppChat: Equatable, Sendable {
    public let id: WhatsAppChatID
    public let title: String
    public let kind: WhatsAppChatKind
    public let unreadCount: Int
    public let lastMessageAt: WhatsAppTimestamp?

    public init?(
        id: WhatsAppChatID,
        title: String,
        kind: WhatsAppChatKind,
        unreadCount: Int,
        lastMessageAt: WhatsAppTimestamp?
    ) {
        guard unreadCount >= 0 else {
            return nil
        }
        self.id = id
        self.title = title
        self.kind = kind
        self.unreadCount = unreadCount
        self.lastMessageAt = lastMessageAt
    }
}

public struct WhatsAppParticipant: Equatable, Sendable {
    public let id: WhatsAppParticipantID
    public let displayName: String?

    public init(id: WhatsAppParticipantID, displayName: String?) {
        self.id = id
        self.displayName = displayName
    }
}

public struct WhatsAppQuote: Equatable, Sendable {
    public let messageID: WhatsAppMessageID
    public let senderID: WhatsAppParticipantID?
    public let body: String?

    public init(
        messageID: WhatsAppMessageID,
        senderID: WhatsAppParticipantID?,
        body: String?
    ) {
        self.messageID = messageID
        self.senderID = senderID
        self.body = body
    }
}

public enum WhatsAppMediaKind: Equatable, Sendable {
    case image
    case video
    case audio
    case document
    case sticker
    case other
}

public struct WhatsAppMediaMetadata: Equatable, Sendable {
    public let kind: WhatsAppMediaKind
    public let mimeType: String?
    public let filename: String?
    public let sizeBytes: Int64?
    public let durationMilliseconds: Int64?
    public let width: Int?
    public let height: Int?

    public init?(
        kind: WhatsAppMediaKind,
        mimeType: String?,
        filename: String?,
        sizeBytes: Int64?,
        durationMilliseconds: Int64?,
        width: Int?,
        height: Int?
    ) {
        let largeValues = [sizeBytes, durationMilliseconds].compactMap { $0 }
        let dimensions = [width, height].compactMap { $0 }
        guard largeValues.allSatisfy({ $0 >= 0 }), dimensions.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        self.kind = kind
        self.mimeType = mimeType
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.durationMilliseconds = durationMilliseconds
        self.width = width
        self.height = height
    }
}

public struct WhatsAppTranslationMetadata: Equatable, Sendable {
    public let sourceLanguage: String?
    public let targetLanguage: String
    public let translatedBody: String
    public let contextMessageCount: Int
    public let translatedAt: WhatsAppTimestamp?

    public init?(
        sourceLanguage: String?,
        targetLanguage: String,
        translatedBody: String,
        contextMessageCount: Int,
        translatedAt: WhatsAppTimestamp?
    ) {
        if let sourceLanguage,
           sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        guard
            !targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            contextMessageCount >= 0
        else {
            return nil
        }
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.translatedBody = translatedBody
        self.contextMessageCount = contextMessageCount
        self.translatedAt = translatedAt
    }
}

public struct WhatsAppMessage: Equatable, Sendable {
    public let id: WhatsAppMessageID
    public let chatID: WhatsAppChatID
    public let senderID: WhatsAppParticipantID?
    public let timestamp: WhatsAppTimestamp
    public let body: String?
    public let fromMe: Bool
    public let quote: WhatsAppQuote?
    public let media: WhatsAppMediaMetadata?
    public let translation: WhatsAppTranslationMetadata?

    public init(
        id: WhatsAppMessageID,
        chatID: WhatsAppChatID,
        senderID: WhatsAppParticipantID?,
        timestamp: WhatsAppTimestamp,
        body: String?,
        fromMe: Bool,
        quote: WhatsAppQuote?,
        media: WhatsAppMediaMetadata?,
        translation: WhatsAppTranslationMetadata?
    ) {
        self.id = id
        self.chatID = chatID
        self.senderID = senderID
        self.timestamp = timestamp
        self.body = body
        self.fromMe = fromMe
        self.quote = quote
        self.media = media
        self.translation = translation
    }
}

public struct WhatsAppMessageCursor: Equatable, Sendable {
    public let beforeMessageID: WhatsAppMessageID?
    public let beforeTimestamp: WhatsAppTimestamp?

    public init?(
        beforeMessageID: WhatsAppMessageID?,
        beforeTimestamp: WhatsAppTimestamp?
    ) {
        guard beforeMessageID != nil || beforeTimestamp != nil else {
            return nil
        }
        self.beforeMessageID = beforeMessageID
        self.beforeTimestamp = beforeTimestamp
    }
}

public struct WhatsAppMessagePage: Equatable, Sendable {
    public let messages: [WhatsAppMessage]
    public let nextCursor: WhatsAppMessageCursor?

    public init(messages: [WhatsAppMessage], nextCursor: WhatsAppMessageCursor?) {
        self.messages = messages
        self.nextCursor = nextCursor
    }
}
