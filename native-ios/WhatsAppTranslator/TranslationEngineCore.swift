import Foundation

public struct TranslationRequestID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.rawValue = value
    }
}

public struct TranslationLanguagePair: Equatable, Hashable, Sendable {
    public let sourceLanguage: String
    public let targetLanguage: String

    public init?(sourceLanguage: String, targetLanguage: String) {
        let source = sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else { return nil }
        self.sourceLanguage = source
        self.targetLanguage = target
    }
}

public struct TranslationModelDescriptor: Equatable, Hashable, Sendable {
    public let identifier: String
    public let version: String

    public init?(identifier: String, version: String) {
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !version.isEmpty else { return nil }
        self.identifier = identifier
        self.version = version
    }
}

public struct TranslationRequest: Equatable, Sendable {
    public let id: TranslationRequestID
    public let revision: Int
    public let languages: TranslationLanguagePair
    public let prompt: TranslationPrompt
    /// The source message supplied to a text provider or local model.
    ///
    /// Older callers may construct a prompt-only request, so this remains
    /// optional for source compatibility. Provider-backed engines reject such
    /// requests with `invalidRequest` rather than guessing from serialized
    /// prompt data.
    public let sourceText: String?

    public init?(
        id: TranslationRequestID,
        revision: Int,
        languages: TranslationLanguagePair,
        prompt: TranslationPrompt,
        sourceText: String? = nil
    ) {
        guard revision > 0 else { return nil }
        self.id = id
        self.revision = revision
        self.languages = languages
        self.prompt = prompt
        if let sourceText,
           sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.sourceText = nil
        } else {
            self.sourceText = sourceText
        }
    }
}

public struct TranslationResult: Equatable, Sendable {
    public let requestID: TranslationRequestID
    public let revision: Int
    public let translatedText: String
    public let model: TranslationModelDescriptor
    public let promptVersion: TranslationPromptVersion

    public init?(
        requestID: TranslationRequestID,
        revision: Int,
        translatedText: String,
        model: TranslationModelDescriptor,
        promptVersion: TranslationPromptVersion
    ) {
        guard
            revision > 0,
            !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        self.requestID = requestID
        self.revision = revision
        self.translatedText = translatedText
        self.model = model
        self.promptVersion = promptVersion
    }
}

public enum TranslationEngineUnavailabilityReason: Equatable, Sendable {
    case unavailable
    case unsupportedLanguagePair
    case notInstalled
    case disabledByPolicy
}

public enum TranslationEngineAvailability: Equatable, Sendable {
    case available
    case unavailable(TranslationEngineUnavailabilityReason)
}

public enum TranslationEngineFailure: Error, Equatable, Sendable {
    case unavailable
    case unsupported
    case transient
    case invalidRequest
    case permanent
    case cancelled

    var allowsFallback: Bool {
        switch self {
        case .unavailable, .unsupported, .transient:
            return true
        case .invalidRequest, .permanent, .cancelled:
            return false
        }
    }
}

public protocol TranslationEngine: Sendable {
    var model: TranslationModelDescriptor { get }

    func availability(for request: TranslationRequest) async -> TranslationEngineAvailability
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

/// A provider that translates plain text without taking a dependency on the
/// prompt format used by a particular model runtime.
///
/// Implementations should throw `TranslationEngineFailure` values for known
/// provider failures. The experimental adapters below map unknown errors to a
/// retryable `.transient` failure so the router can still make a typed,
/// bounded fallback decision.
public protocol TranslationTextProvider: Sendable {
    var identifier: String { get }

    func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability

    func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String
}

/// A provider pipeline for language pairs that are not available directly.
///
/// For example, Indonesian -> Polish is attempted as Indonesian -> English ->
/// Polish. Each hop is independently availability-checked and the second hop
/// never runs when the first hop is unavailable or fails.
public struct TwoStepTranslationProvider: TranslationTextProvider {
    public let identifier: String
    public let intermediateLanguage: String

    private let sourceToIntermediate: any TranslationTextProvider
    private let intermediateToTarget: any TranslationTextProvider

    public init?(
        intermediateLanguage: String = "en",
        sourceToIntermediate: any TranslationTextProvider,
        intermediateToTarget: any TranslationTextProvider,
        identifier: String? = nil
    ) {
        let intermediate = intermediateLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intermediate.isEmpty else { return nil }

        let defaultIdentifier = "two-step/\(sourceToIntermediate.identifier)->\(intermediate)->\(intermediateToTarget.identifier)"
        let resolvedIdentifier = (identifier ?? defaultIdentifier)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedIdentifier.isEmpty else { return nil }

        self.identifier = resolvedIdentifier
        self.intermediateLanguage = intermediate
        self.sourceToIntermediate = sourceToIntermediate
        self.intermediateToTarget = intermediateToTarget
    }

    public func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability {
        guard let pair = TranslationLanguagePair(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) else {
            return .unavailable(.unsupportedLanguagePair)
        }

        let first = await sourceToIntermediate.availability(
            sourceLanguage: pair.sourceLanguage,
            targetLanguage: intermediateLanguage
        )
        guard case .available = first else {
            return first
        }

        return await intermediateToTarget.availability(
            sourceLanguage: intermediateLanguage,
            targetLanguage: pair.targetLanguage
        )
    }

    public func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        guard
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let pair = TranslationLanguagePair(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        else {
            throw TranslationEngineFailure.invalidRequest
        }

        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        let intermediateText: String
        do {
            intermediateText = try await sourceToIntermediate.translate(
                text: text,
                sourceLanguage: pair.sourceLanguage,
                targetLanguage: intermediateLanguage
            )
        } catch {
            throw normalizedProviderFailure(error)
        }

        guard !intermediateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationEngineFailure.permanent
        }

        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        let translatedText: String
        do {
            translatedText = try await intermediateToTarget.translate(
                text: intermediateText,
                sourceLanguage: intermediateLanguage,
                targetLanguage: pair.targetLanguage
            )
        } catch {
            throw normalizedProviderFailure(error)
        }

        guard !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationEngineFailure.permanent
        }

        return translatedText
    }
}

/// Adapts a plain-text two-step provider to the request/result contract used
/// by `TranslationEngineRouter`.
public struct TwoStepTranslationEngine: TranslationEngine {
    public let model: TranslationModelDescriptor

    private let provider: any TranslationTextProvider

    public init(
        provider: any TranslationTextProvider,
        model: TranslationModelDescriptor
    ) {
        self.provider = provider
        self.model = model
    }

    public init?(
        provider: any TranslationTextProvider,
        version: String = "experimental-v1"
    ) {
        guard let model = TranslationModelDescriptor(
            identifier: provider.identifier,
            version: version
        ) else {
            return nil
        }
        self.init(provider: provider, model: model)
    }

    public func availability(for request: TranslationRequest) async -> TranslationEngineAvailability {
        await provider.availability(
            sourceLanguage: request.languages.sourceLanguage,
            targetLanguage: request.languages.targetLanguage
        )
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let sourceText = request.sourceText else {
            throw TranslationEngineFailure.invalidRequest
        }
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        let translatedText: String
        do {
            translatedText = try await provider.translate(
                text: sourceText,
                sourceLanguage: request.languages.sourceLanguage,
                targetLanguage: request.languages.targetLanguage
            )
        } catch {
            throw normalizedProviderFailure(error)
        }

        guard let result = TranslationResult(
            requestID: request.id,
            revision: request.revision,
            translatedText: translatedText,
            model: model,
            promptVersion: request.prompt.version
        ) else {
            throw TranslationEngineFailure.permanent
        }
        return result
    }
}

/// A multilingual on-device model seam. The concrete runtime can be backed by
/// a licensed Core ML, MLX, or llama.cpp model without changing router logic.
public protocol MultilingualLocalModel: Sendable {
    var identifier: String { get }

    func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability

    /// Receives the complete request that entered `TranslationEngine`.
    ///
    /// Implementations must use `request.sourceText` as the explicit source
    /// message and may use `request.prompt` for its immutable instructions and
    /// contextual, untrusted chat payload. They must not reconstruct the
    /// source message by decoding `request.prompt.untrustedInput`.
    func translate(_ request: TranslationRequest) async throws -> String
}

/// Adapts a multilingual local model to the common translation engine route.
public struct LocalMultilingualModelEngine: TranslationEngine {
    public let model: TranslationModelDescriptor

    private let localModel: any MultilingualLocalModel

    public init(
        localModel: any MultilingualLocalModel,
        model: TranslationModelDescriptor
    ) {
        self.localModel = localModel
        self.model = model
    }

    public init?(
        localModel: any MultilingualLocalModel,
        version: String = "experimental-v1"
    ) {
        guard let model = TranslationModelDescriptor(
            identifier: localModel.identifier,
            version: version
        ) else {
            return nil
        }
        self.init(localModel: localModel, model: model)
    }

    public func availability(for request: TranslationRequest) async -> TranslationEngineAvailability {
        await localModel.availability(
            sourceLanguage: request.languages.sourceLanguage,
            targetLanguage: request.languages.targetLanguage
        )
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard request.sourceText != nil else {
            throw TranslationEngineFailure.invalidRequest
        }
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        let translatedText: String
        do {
            // Pass the original request through unchanged so a local model
            // receives the versioned prompt and its complete context as well
            // as the explicit source message.
            translatedText = try await localModel.translate(request)
        } catch {
            throw normalizedProviderFailure(error)
        }

        guard let result = TranslationResult(
            requestID: request.id,
            revision: request.revision,
            translatedText: translatedText,
            model: model,
            promptVersion: request.prompt.version
        ) else {
            throw TranslationEngineFailure.permanent
        }
        return result
    }
}

/// Explicit placeholder used until a real, licensed multilingual model is
/// selected and bundled or downloaded by the app.
public struct UnavailableMultilingualLocalModel: MultilingualLocalModel {
    public let identifier: String

    public init(identifier: String = "multilingual-local-model") {
        self.identifier = identifier
    }

    public func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability {
        .unavailable(.notInstalled)
    }

    public func translate(_ request: TranslationRequest) async throws -> String {
        throw TranslationEngineFailure.unavailable
    }
}

private func normalizedProviderFailure(_ error: Error) -> TranslationEngineFailure {
    if let failure = error as? TranslationEngineFailure {
        return failure
    }
    if error is CancellationError {
        return .cancelled
    }
    return .transient
}

public enum TranslationEngineAttemptFailure: Equatable, Sendable {
    case unavailable(
        model: TranslationModelDescriptor,
        reason: TranslationEngineUnavailabilityReason
    )
    case execution(
        model: TranslationModelDescriptor,
        failure: TranslationEngineFailure
    )
}

public enum TranslationEngineContractViolation: Equatable, Sendable {
    case unexpectedErrorType
    case mismatchedRequestID
    case mismatchedRevision
    case mismatchedPromptVersion
    case mismatchedModelDescriptor
}

public enum TranslationRoutingError: Error, Equatable, Sendable {
    case noEnginesConfigured
    case duplicateModelDescriptor(TranslationModelDescriptor)
    case cancelled
    case terminalFailure(
        model: TranslationModelDescriptor,
        failure: TranslationEngineFailure
    )
    case contractViolation(
        model: TranslationModelDescriptor,
        violation: TranslationEngineContractViolation
    )
    case exhausted([TranslationEngineAttemptFailure])
}

public struct TranslationEngineRouter: Sendable {
    private let engines: [any TranslationEngine]

    public init(engines: [any TranslationEngine]) throws {
        guard !engines.isEmpty else {
            throw TranslationRoutingError.noEnginesConfigured
        }

        var seen = Set<TranslationModelDescriptor>()
        for engine in engines {
            guard seen.insert(engine.model).inserted else {
                throw TranslationRoutingError.duplicateModelDescriptor(engine.model)
            }
        }

        self.engines = engines
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        var attempts: [TranslationEngineAttemptFailure] = []

        for engine in engines {
            guard !Task.isCancelled else {
                throw TranslationRoutingError.cancelled
            }

            switch await engine.availability(for: request) {
            case .available:
                break
            case .unavailable(let reason):
                attempts.append(.unavailable(model: engine.model, reason: reason))
                continue
            }

            guard !Task.isCancelled else {
                throw TranslationRoutingError.cancelled
            }

            do {
                let result = try await engine.translate(request)
                try validate(result, for: request, engine: engine)
                return result
            } catch let failure as TranslationEngineFailure {
                if failure == .cancelled {
                    throw TranslationRoutingError.cancelled
                }
                if failure.allowsFallback {
                    attempts.append(.execution(model: engine.model, failure: failure))
                    continue
                }
                throw TranslationRoutingError.terminalFailure(
                    model: engine.model,
                    failure: failure
                )
            } catch is CancellationError {
                throw TranslationRoutingError.cancelled
            } catch let routingError as TranslationRoutingError {
                throw routingError
            } catch {
                throw TranslationRoutingError.contractViolation(
                    model: engine.model,
                    violation: .unexpectedErrorType
                )
            }
        }

        throw TranslationRoutingError.exhausted(attempts)
    }

    private func validate(
        _ result: TranslationResult,
        for request: TranslationRequest,
        engine: any TranslationEngine
    ) throws {
        guard result.requestID == request.id else {
            throw TranslationRoutingError.contractViolation(
                model: engine.model,
                violation: .mismatchedRequestID
            )
        }
        guard result.revision == request.revision else {
            throw TranslationRoutingError.contractViolation(
                model: engine.model,
                violation: .mismatchedRevision
            )
        }
        guard result.promptVersion == request.prompt.version else {
            throw TranslationRoutingError.contractViolation(
                model: engine.model,
                violation: .mismatchedPromptVersion
            )
        }
        guard result.model == engine.model else {
            throw TranslationRoutingError.contractViolation(
                model: engine.model,
                violation: .mismatchedModelDescriptor
            )
        }
    }
}
