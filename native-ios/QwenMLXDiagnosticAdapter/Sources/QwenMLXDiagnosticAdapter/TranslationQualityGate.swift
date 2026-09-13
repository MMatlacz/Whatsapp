import Foundation

/// A conservative diagnostic output gate. It only detects mechanical output
/// failures; it does not score meaning, fluency, tone, or context handling.
/// A non-empty output therefore remains `requiresHumanReview` and can never be
/// treated as a quality pass by this package.
public enum TranslationQualityGateStatus: String, Codable, Equatable, Sendable {
    case blocked
    case requiresHumanReview
}

public enum TranslationQualityGateReason: String, Codable, Equatable, Sendable {
    case missingOutput
    case emptyOutput
    case nonReturnedExecution
    case thinkingOnlyOutput
    case interruptedOutput
    case truncatedOutput
    case controlTokenLeakage
    case unchangedSource
    case semanticQualityUnverified
}

public struct TranslationQualityGateDecision: Codable, Equatable, Sendable {
    public let status: TranslationQualityGateStatus
    public let reasons: [TranslationQualityGateReason]

    public init(
        status: TranslationQualityGateStatus,
        reasons: [TranslationQualityGateReason]
    ) {
        self.status = status
        self.reasons = reasons
    }

    public var mayBeSent: Bool { false }
    public var requiresHumanReview: Bool { status == .requiresHumanReview }
}

public enum TranslationQualityGate {
    /// Evaluate an already generated string. The optional execution metadata
    /// lets a caller reject an interrupted or token-budget-exhausted stream
    /// before anyone mistakes its partial text for a translation.
    public static func evaluate(
        sourceText: String,
        output: String?,
        termination: TranslationBenchmarkTermination = .returned,
        outputValidity: TranslationBenchmarkOutputValidity? = nil,
        finishReason: String? = nil,
        reachedGenerationLimit: Bool = false
    ) -> TranslationQualityGateDecision {
        var reasons: [TranslationQualityGateReason] = []

        guard let output else {
            return blocked(.missingOutput)
        }

        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            return blocked(.emptyOutput)
        }

        if termination != .returned {
            reasons.append(.nonReturnedExecution)
        }

        if let outputValidity {
            switch outputValidity {
            case .emptyText:
                reasons.append(.emptyOutput)
            case .thinkingOnly:
                reasons.append(.thinkingOnlyOutput)
            case .truncated:
                reasons.append(.truncatedOutput)
            case .interrupted:
                reasons.append(.interruptedOutput)
            case .notProduced:
                reasons.append(.missingOutput)
            case .validText, .unknown:
                break
            }
        }

        if finishReason == "cancelled" {
            reasons.append(.interruptedOutput)
        }
        if reachedGenerationLimit {
            reasons.append(.truncatedOutput)
        }
        if containsControlToken(trimmedOutput) {
            reasons.append(.controlTokenLeakage)
        }
        if !trimmedSource.isEmpty && normalized(trimmedSource) == normalized(trimmedOutput) {
            reasons.append(.unchangedSource)
        }

        reasons = Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
        guard reasons.isEmpty else {
            return TranslationQualityGateDecision(status: .blocked, reasons: reasons)
        }

        return TranslationQualityGateDecision(
            status: .requiresHumanReview,
            reasons: [.semanticQualityUnverified]
        )
    }

    public static func evaluate(
        _ result: TranslationBenchmarkResultRecord
    ) -> TranslationQualityGateDecision {
        evaluate(
            sourceText: result.input,
            output: result.output,
            termination: result.termination,
            outputValidity: result.outputValidity,
            finishReason: result.finishReason,
            reachedGenerationLimit: result.outputValidity == .truncated
        )
    }

    private static func blocked(
        _ reason: TranslationQualityGateReason
    ) -> TranslationQualityGateDecision {
        TranslationQualityGateDecision(status: .blocked, reasons: [reason])
    }

    private static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func containsControlToken(_ value: String) -> Bool {
        [
            "<bos>", "<eos>", "<start_of_turn>", "<end_of_turn>",
            "<|begin_of_text|>", "<|end_of_text|>", "<|im_start|>", "<|im_end|>",
            "<think>", "</think>",
        ].contains { value.localizedCaseInsensitiveContains($0) }
    }
}
