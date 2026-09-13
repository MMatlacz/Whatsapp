import Foundation

/// The model-specific content object expected by TranslateGemma's chat
/// template. Keeping this separate from `TranslationRequest` makes the
/// diagnostic adapter explicit about the template it is evaluating.
public struct TranslateGemmaTextContent: Codable, Equatable, Sendable {
    public let type: String
    public let sourceLanguageCode: String
    public let targetLanguageCode: String
    public let text: String

    public init(
        sourceLanguageCode: String,
        targetLanguageCode: String,
        text: String
    ) {
        self.type = "text"
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case type
        case sourceLanguageCode = "source_lang_code"
        case targetLanguageCode = "target_lang_code"
        case text
    }
}

/// A vocabulary note supplied by a user or a local correction store. It is
/// deliberately a meaning note rather than an asserted source-to-Polish
/// alignment; the model must still produce a complete translation and the
/// quality gate still requires human review.
public struct TranslateGemmaVocabularyHint: Equatable, Sendable {
    public let sourceText: String
    public let meaningNote: String

    public init(sourceText: String, meaningNote: String) throws {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !meaningNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslateGemmaPrompt.Failure.invalidVocabularyHint
        }
        guard sourceText.utf8.count <= 256,
              meaningNote.utf8.count <= 512,
              !TranslateGemmaPrompt.containsControlToken(sourceText),
              !TranslateGemmaPrompt.containsControlToken(meaningNote) else {
            throw TranslateGemmaPrompt.Failure.invalidVocabularyHint
        }
        self.sourceText = sourceText
        self.meaningNote = meaningNote
    }
}

/// A bounded, local-only TranslateGemma prompt. This is a diagnostic prompt
/// builder, not a production translation contract.
public struct TranslateGemmaPrompt: Equatable, Sendable {
    public static let version = "translategemma-native-template-v1"
    public static let sourceLanguageCode = "id"
    public static let targetLanguageCode = "pl"
    public static let maximumTargetUTF8Bytes = 8 * 1_024
    public static let maximumGuidanceUTF8Bytes = 2 * 1_024
    public static let maximumVocabularyHintCount = 24
    public static let maximumVocabularyHintsUTF8Bytes = 2 * 1_024

    public enum Failure: Error, Equatable, Sendable {
        case emptyTarget
        case targetTooLarge
        case guidanceTooLarge
        case controlTokenInInput
        case tooManyVocabularyHints
        case vocabularyHintsTooLarge
        case invalidVocabularyHint
    }

    public let targetText: String
    public let guidance: String
    public let vocabularyHints: [TranslateGemmaVocabularyHint]

    public init(
        targetText: String,
        guidance: String = "",
        vocabularyHints: [TranslateGemmaVocabularyHint] = []
    ) throws {
        guard !targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.emptyTarget
        }
        guard targetText.utf8.count <= Self.maximumTargetUTF8Bytes else {
            throw Failure.targetTooLarge
        }
        guard guidance.utf8.count <= Self.maximumGuidanceUTF8Bytes else {
            throw Failure.guidanceTooLarge
        }
        guard !Self.containsControlToken(targetText), !Self.containsControlToken(guidance) else {
            throw Failure.controlTokenInInput
        }
        guard vocabularyHints.count <= Self.maximumVocabularyHintCount else {
            throw Failure.tooManyVocabularyHints
        }
        let hintBytes = vocabularyHints.reduce(0) {
            $0 + $1.sourceText.utf8.count + $1.meaningNote.utf8.count
        }
        guard hintBytes <= Self.maximumVocabularyHintsUTF8Bytes else {
            throw Failure.vocabularyHintsTooLarge
        }

        self.targetText = targetText
        self.guidance = guidance
        self.vocabularyHints = vocabularyHints
    }

    /// The text field passed to the model-specific content object. Guidance
    /// is explicitly bounded and labelled as data so it cannot silently
    /// replace the target message.
    public var contentText: String {
        var sections: [String] = []
        let trimmedGuidance = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGuidance.isEmpty {
            sections.append(
                "Translator guidance (do not translate):\n\(guidance)"
            )
        }
        if !vocabularyHints.isEmpty {
            let notes = vocabularyHints
                .sorted {
                    $0.sourceText.localizedCompare($1.sourceText) == .orderedAscending
                }
                .map { "- \($0.sourceText): \($0.meaningNote)" }
                .joined(separator: "\n")
            sections.append("Vocabulary notes (do not translate):\n\(notes)")
        }
        guard !sections.isEmpty else { return targetText }
        sections.append("Target text (translate only this):\n\(targetText)")
        return sections.joined(separator: "\n")
    }

    public var content: TranslateGemmaTextContent {
        TranslateGemmaTextContent(
            sourceLanguageCode: Self.sourceLanguageCode,
            targetLanguageCode: Self.targetLanguageCode,
            text: contentText
        )
    }

    /// Convert to the raw message shape consumed by
    /// `Tokenizer.applyChatTemplate(messages:)`.
    public var modelMessage: [String: any Sendable] {
        [
            "role": "user",
            "content": [[
                "type": content.type,
                "source_lang_code": content.sourceLanguageCode,
                "target_lang_code": content.targetLanguageCode,
                "text": content.text,
            ] as [String: any Sendable]],
        ]
    }

    fileprivate static func containsControlToken(_ value: String) -> Bool {
        [
            "<bos>", "<eos>", "<start_of_turn>", "<end_of_turn>",
            "<|begin_of_text|>", "<|end_of_text|>", "<|im_start|>", "<|im_end|>",
        ].contains { value.localizedCaseInsensitiveContains($0) }
    }
}
