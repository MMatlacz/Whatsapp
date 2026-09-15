import Foundation

#if SWIFT_PACKAGE
import WhatsAppDomainCore
#endif

public struct TranslationContextSourceSummary: Equatable, Sendable {
    public let version: Int
    public let body: String
    public let sourceMessageCount: Int
    public let throughMessageID: WhatsAppMessageID
    public let throughTimestamp: WhatsAppTimestamp

    public init(
        version: Int,
        body: String,
        sourceMessageCount: Int,
        throughMessageID: WhatsAppMessageID,
        throughTimestamp: WhatsAppTimestamp
    ) {
        self.version = version
        self.body = body
        self.sourceMessageCount = sourceMessageCount
        self.throughMessageID = throughMessageID
        self.throughTimestamp = throughTimestamp
    }
}

public protocol TranslationContextSource: Sendable {
    func message(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID
    ) async throws -> WhatsAppMessage?

    func recentTextMessages(
        chatID: WhatsAppChatID,
        before target: WhatsAppMessage,
        limit: Int
    ) async throws -> [WhatsAppMessage]

    func latestSummary(chatID: WhatsAppChatID) async throws -> TranslationContextSourceSummary?
}

public enum TranslationContextAssemblyError: Error, Equatable, Sendable {
    case missingTarget(chatID: WhatsAppChatID, messageID: WhatsAppMessageID)
    case invalidRecentTurnLimit(Int)
}

public struct TranslationContextAssembler: Sendable {
    private let source: any TranslationContextSource
    private let builder: TranslationContextBuilder

    public init(
        source: any TranslationContextSource,
        builder: TranslationContextBuilder = TranslationContextBuilder()
    ) {
        self.source = source
        self.builder = builder
    }

    public func assemble(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        recentTurnLimit: Int = TranslationContextBuilder.defaultRecentTurnLimit
    ) async throws -> TranslationContext {
        guard (0...TranslationContextBuilder.maximumRecentTurnLimit).contains(recentTurnLimit) else {
            throw TranslationContextAssemblyError.invalidRecentTurnLimit(recentTurnLimit)
        }
        guard let target = try await source.message(chatID: chatID, messageID: messageID) else {
            throw TranslationContextAssemblyError.missingTarget(chatID: chatID, messageID: messageID)
        }

        var conversation = try await source.recentTextMessages(
            chatID: chatID,
            before: target,
            limit: recentTurnLimit
        )

        if let quotedMessageID = target.quote?.messageID,
           !conversation.contains(where: { $0.id == quotedMessageID }),
           let quoted = try await source.message(chatID: chatID, messageID: quotedMessageID),
           comesBefore(quoted, target: target) {
            conversation.append(quoted)
        }

        let summary = try await compatibleSummary(chatID: chatID, target: target)
        return try builder.build(
            target: target,
            conversation: conversation,
            summary: summary,
            recentTurnLimit: recentTurnLimit
        )
    }

    private func compatibleSummary(
        chatID: WhatsAppChatID,
        target: WhatsAppMessage
    ) async throws -> TranslationContextSummary? {
        guard let stored = try await source.latestSummary(chatID: chatID),
              boundaryPrecedesTarget(
                timestamp: stored.throughTimestamp,
                messageID: stored.throughMessageID,
                target: target
              ) else {
            return nil
        }
        return TranslationContextSummary(
            version: stored.version,
            body: stored.body,
            sourceMessageCount: stored.sourceMessageCount
        )
    }

    private func comesBefore(_ message: WhatsAppMessage, target: WhatsAppMessage) -> Bool {
        boundaryPrecedesTarget(timestamp: message.timestamp, messageID: message.id, target: target)
    }

    private func boundaryPrecedesTarget(
        timestamp: WhatsAppTimestamp,
        messageID: WhatsAppMessageID,
        target: WhatsAppMessage
    ) -> Bool {
        if timestamp != target.timestamp { return timestamp < target.timestamp }
        return messageID.rawValue < target.id.rawValue
    }
}
