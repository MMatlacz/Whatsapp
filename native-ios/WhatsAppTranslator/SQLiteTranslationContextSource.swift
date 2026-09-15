import Foundation

#if SWIFT_PACKAGE
import PersistenceCore
import TranslationCore
import WhatsAppDomainCore
#endif

public final class SQLiteTranslationContextSource: TranslationContextSource, @unchecked Sendable {
    public static let maximumScannedMessages = 256

    private let store: SQLiteContextStore

    public init(store: SQLiteContextStore) {
        self.store = store
    }

    public func message(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID
    ) async throws -> WhatsAppMessage? {
        try store.core.message(chatID: chatID, messageID: messageID)
    }

    public func recentTextMessages(
        chatID: WhatsAppChatID,
        before target: WhatsAppMessage,
        limit: Int
    ) async throws -> [WhatsAppMessage] {
        guard limit > 0 else { return [] }

        let scanBudget = min(Self.maximumScannedMessages, max(32, limit * 8))
        guard let initialCursor = WhatsAppMessageCursor(
            beforeMessageID: target.id,
            beforeTimestamp: target.timestamp
        ) else {
            return []
        }

        var cursor: WhatsAppMessageCursor? = initialCursor
        var scanned = 0
        var textMessages: [WhatsAppMessage] = []
        textMessages.reserveCapacity(limit)

        while scanned < scanBudget, textMessages.count < limit, let currentCursor = cursor {
            let pageLimit = min(100, scanBudget - scanned)
            let page = try store.core.messages(
                chatID: chatID,
                before: currentCursor,
                limit: pageLimit
            )
            scanned += page.messages.count

            for message in page.messages {
                guard let body = message.body,
                      !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                textMessages.append(message)
                if textMessages.count == limit { break }
            }

            guard !page.messages.isEmpty, let next = page.nextCursor else { break }
            cursor = next
        }

        return Array(textMessages.prefix(limit).reversed())
    }

    public func latestSummary(chatID: WhatsAppChatID) async throws -> TranslationContextSourceSummary? {
        guard let summary = try store.latestSummary(chatID: chatID) else { return nil }
        return TranslationContextSourceSummary(
            version: summary.version,
            body: summary.summaryText,
            sourceMessageCount: summary.sourceMessageCount,
            throughMessageID: summary.throughMessageID,
            throughTimestamp: summary.throughTimestamp
        )
    }
}
