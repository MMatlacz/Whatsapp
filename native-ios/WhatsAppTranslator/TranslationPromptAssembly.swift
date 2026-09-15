import Foundation

#if SWIFT_PACKAGE
import WhatsAppDomainCore
#endif

public struct TranslationPromptContextMetadata: Equatable, Sendable {
    public let recentTurnCount: Int
    public let hasQuotedTurn: Bool
    public let summaryVersion: Int?
    public let summarySourceMessageCount: Int?

    public init(
        recentTurnCount: Int,
        hasQuotedTurn: Bool,
        summaryVersion: Int?,
        summarySourceMessageCount: Int?
    ) {
        self.recentTurnCount = recentTurnCount
        self.hasQuotedTurn = hasQuotedTurn
        self.summaryVersion = summaryVersion
        self.summarySourceMessageCount = summarySourceMessageCount
    }
}

public struct TranslationPromptContract: Equatable, Sendable {
    public let prompt: TranslationPrompt
    public let sourceLanguage: String
    public let targetLanguage: String
    public let contextMetadata: TranslationPromptContextMetadata

    public init(
        prompt: TranslationPrompt,
        sourceLanguage: String,
        targetLanguage: String,
        contextMetadata: TranslationPromptContextMetadata
    ) {
        self.prompt = prompt
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.contextMetadata = contextMetadata
    }
}

public struct TranslationPromptContractBuilder: Sendable {
    private let promptBuilder: TranslationPromptBuilder

    public init(promptBuilder: TranslationPromptBuilder = TranslationPromptBuilder()) {
        self.promptBuilder = promptBuilder
    }

    public func build(
        sourceLanguage: String,
        targetLanguage: String,
        context: TranslationContext
    ) throws -> TranslationPromptContract {
        let prompt = try promptBuilder.build(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            context: context
        )
        return TranslationPromptContract(
            prompt: prompt,
            sourceLanguage: sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines),
            targetLanguage: targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines),
            contextMetadata: TranslationPromptContextMetadata(
                recentTurnCount: context.recentTurns.count,
                hasQuotedTurn: context.quotedTurn != nil,
                summaryVersion: context.summary?.version,
                summarySourceMessageCount: context.summary?.sourceMessageCount
            )
        )
    }
}

public struct PersistenceBackedTranslationPromptAssembler: Sendable {
    private let contextAssembler: TranslationContextAssembler
    private let contractBuilder: TranslationPromptContractBuilder

    public init(
        source: any TranslationContextSource,
        contextBuilder: TranslationContextBuilder = TranslationContextBuilder(),
        promptBuilder: TranslationPromptBuilder = TranslationPromptBuilder()
    ) {
        contextAssembler = TranslationContextAssembler(source: source, builder: contextBuilder)
        contractBuilder = TranslationPromptContractBuilder(promptBuilder: promptBuilder)
    }

    public func assemble(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        sourceLanguage: String,
        targetLanguage: String,
        recentTurnLimit: Int = TranslationContextBuilder.defaultRecentTurnLimit
    ) async throws -> TranslationPromptContract {
        let context = try await contextAssembler.assemble(
            chatID: chatID,
            messageID: messageID,
            recentTurnLimit: recentTurnLimit
        )
        return try contractBuilder.build(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            context: context
        )
    }
}
