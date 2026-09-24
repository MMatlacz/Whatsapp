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

    public var contextMessageCount: Int {
        recentTurnCount + (hasQuotedTurn ? 1 : 0)
    }
}

public struct TranslationPromptContract: Equatable, Sendable {
    public let prompt: TranslationPrompt
    public let sourceLanguage: String
    public let targetLanguage: String
    public let contextMetadata: TranslationPromptContextMetadata
    public let contextHash: String

    public init(
        prompt: TranslationPrompt,
        sourceLanguage: String,
        targetLanguage: String,
        contextMetadata: TranslationPromptContextMetadata,
        contextHash: String? = nil
    ) {
        self.prompt = prompt
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.contextMetadata = contextMetadata
        self.contextHash = contextHash ?? Self.stableHash(prompt.untrustedInput)
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "fnv1a-%016llx", hash)
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
    public static let productionRecentTurnLimit = 6
    public static let maximumRecentContextUTF8Bytes = 2_400
    public static let maximumQuotedTurnUTF8Bytes = 800

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
        recentTurnLimit: Int = Self.productionRecentTurnLimit
    ) async throws -> TranslationPromptContract {
        let context = try await contextAssembler.assemble(
            chatID: chatID,
            messageID: messageID,
            recentTurnLimit: recentTurnLimit
        )
        return try contractBuilder.build(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            context: Self.applyProductionBudget(context)
        )
    }

    private static func applyProductionBudget(_ context: TranslationContext) -> TranslationContext {
        var remainingRecentBytes = maximumRecentContextUTF8Bytes
        var boundedRecent: [TranslationContextTurn] = []
        boundedRecent.reserveCapacity(context.recentTurns.count)

        for turn in context.recentTurns.reversed() {
            guard remainingRecentBytes > 0 else { break }
            let body = clippedUTF8(turn.body, maxBytes: remainingRecentBytes)
            guard !body.isEmpty else { continue }
            boundedRecent.append(TranslationContextTurn(speaker: turn.speaker, body: body))
            remainingRecentBytes -= body.utf8.count
        }
        boundedRecent.reverse()

        let boundedQuoted = context.quotedTurn.map {
            TranslationQuotedTurn(
                speaker: $0.speaker,
                body: clippedUTF8($0.body, maxBytes: maximumQuotedTurnUTF8Bytes)
            )
        }

        return TranslationContext(
            target: context.target,
            recentTurns: boundedRecent,
            quotedTurn: boundedQuoted,
            summary: context.summary
        )
    }

    private static func clippedUTF8(_ value: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        guard value.utf8.count > maxBytes else { return value }

        var result = ""
        var usedBytes = 0
        for character in value {
            let fragment = String(character)
            let fragmentBytes = fragment.utf8.count
            guard usedBytes + fragmentBytes <= maxBytes else { break }
            result.append(character)
            usedBytes += fragmentBytes
        }
        return result
    }
}
