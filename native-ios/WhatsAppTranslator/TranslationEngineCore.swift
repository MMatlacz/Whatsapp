import Foundation

public struct TranslationRequestID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.rawValue = value
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
    public let prompt: TranslationPrompt

    public init?(id: TranslationRequestID, revision: Int, prompt: TranslationPrompt) {
        guard revision > 0 else { return nil }
        self.id = id
        self.revision = revision
        self.prompt = prompt
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
