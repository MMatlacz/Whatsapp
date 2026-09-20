import Foundation
#if SWIFT_PACKAGE
import TranslationCore
#endif

/// Thin compatibility adapter while NativeTranslationModel still owns revision persistence/UI state.
/// All actual model execution goes through the shared TranslationEngine contract.
actor EngineBackedNativeRetranslator: NativeRetranslator {
    nonisolated let isValidated: Bool
    private let engine: (any TranslationEngine)?
    private let router: TranslationEngineRouter?
    private let promptBuilder: TranslationPromptBuilder
    private var inferenceActive = false

    init(
        engine: any TranslationEngine,
        isValidated: Bool = false,
        promptBuilder: TranslationPromptBuilder = TranslationPromptBuilder()
    ) {
        self.engine = engine
        self.router = nil
        self.isValidated = isValidated
        self.promptBuilder = promptBuilder
    }

    init(
        router: TranslationEngineRouter,
        isValidated: Bool = false,
        promptBuilder: TranslationPromptBuilder = TranslationPromptBuilder()
    ) {
        self.engine = nil
        self.router = router
        self.isValidated = isValidated
        self.promptBuilder = promptBuilder
    }

    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart] {
        try await acquireInferenceSlot(waitIfBusy: request.userInitiated)
        defer { inferenceActive = false }
        guard
            let requestID = TranslationRequestID(rawValue: "\(request.key.chatID):\(request.key.messageID):\(request.revision)"),
            let languages = TranslationLanguagePair(
                sourceLanguage: request.key.sourceLanguage,
                targetLanguage: request.key.targetLanguage
            )
        else { throw NativeRetranslationFailure.invalidInput }

        let context = TranslationContext(
            target: TranslationTarget(speaker: .unknown, body: request.original),
            recentTurns: [], quotedTurn: nil, summary: nil
        )
        let prompt: TranslationPrompt
        do {
            prompt = try promptBuilder.build(
                sourceLanguage: languages.sourceLanguage,
                targetLanguage: languages.targetLanguage,
                context: context
            )
        } catch {
            throw NativeRetranslationFailure.invalidInput
        }
        guard let engineRequest = TranslationRequest(
            id: requestID,
            revision: request.revision,
            languages: languages,
            prompt: prompt,
            sourceText: request.original,
            revisionGuidance: TranslationRevisionGuidance(
                previousTranslation: request.previousTranslation,
                instruction: request.comment,
                userInitiated: request.userInitiated
            )
        ) else { throw NativeRetranslationFailure.invalidInput }

        do {
            let result: TranslationResult
            if let router {
                result = try await router.translate(engineRequest)
            } else if let engine {
                switch await engine.availability(for: engineRequest) {
                case .available:
                    break
                case .unavailable:
                    throw NativeRetranslationFailure.unavailable
                }
                result = try await engine.translate(engineRequest)
            } else {
                throw NativeRetranslationFailure.unavailable
            }
            return [.init(
                id: "engine-\(request.revision)",
                source: nil,
                translation: result.translatedText
            )]
        } catch let failure as NativeRetranslationFailure {
            throw failure
        } catch let failure as TranslationEngineFailure {
            throw Self.nativeFailure(failure)
        } catch let failure as TranslationRoutingError {
            throw Self.nativeFailure(failure)
        } catch is CancellationError {
            throw NativeRetranslationFailure.cancelled
        } catch {
            throw NativeRetranslationFailure.unavailable
        }
    }

    private func acquireInferenceSlot(waitIfBusy: Bool) async throws {
        while inferenceActive {
            guard waitIfBusy else { throw NativeRetranslationFailure.busy }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        inferenceActive = true
    }

    private static func nativeFailure(_ failure: TranslationEngineFailure) -> NativeRetranslationFailure {
        switch failure {
        case .unavailable, .unsupported:
            return .unavailable
        case .transient:
            return .incomplete
        case .invalidRequest:
            return .invalidInput
        case .permanent:
            return .integrity
        case .cancelled:
            return .cancelled
        }
    }

    private static func nativeFailure(_ failure: TranslationRoutingError) -> NativeRetranslationFailure {
        switch failure {
        case .cancelled:
            return .cancelled
        case .terminalFailure(_, let underlying):
            return nativeFailure(underlying)
        case .contractViolation(_, _), .duplicateModelDescriptor(_), .noEnginesConfigured:
            return .integrity
        case .exhausted:
            return .unavailable
        }
    }
}
