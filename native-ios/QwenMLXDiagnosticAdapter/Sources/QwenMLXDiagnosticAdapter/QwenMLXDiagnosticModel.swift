import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import TranslationCore

public struct QwenMLXDiagnosticLimits: Equatable, Sendable {
    public let maxGeneratedTokens: Int
    public let maxSourceUTF8Bytes: Int
    public let maxPromptUTF8Bytes: Int

    public init?(
        maxGeneratedTokens: Int,
        maxSourceUTF8Bytes: Int,
        maxPromptUTF8Bytes: Int
    ) {
        guard
            maxGeneratedTokens > 0,
            maxSourceUTF8Bytes > 0,
            maxPromptUTF8Bytes > 0
        else {
            return nil
        }

        self.maxGeneratedTokens = maxGeneratedTokens
        self.maxSourceUTF8Bytes = maxSourceUTF8Bytes
        self.maxPromptUTF8Bytes = maxPromptUTF8Bytes
    }

    public static let benchmark = QwenMLXDiagnosticLimits(
        maxGeneratedTokens: 512,
        maxSourceUTF8Bytes: 16 * 1_024,
        maxPromptUTF8Bytes: 256 * 1_024
    )!
}

protocol QwenMLXGenerating: Sendable {
    func generate(
        request: TranslationRequest,
        limits: QwenMLXDiagnosticLimits
    ) async throws -> String
}

public struct QwenMLXDiagnosticModel: MultilingualLocalModel, Sendable {
    public let identifier: String

    private let artifacts: QwenMLXVerifiedArtifacts
    private let limits: QwenMLXDiagnosticLimits
    private let generator: any QwenMLXGenerating

    public init(
        verifiedArtifacts: QwenMLXVerifiedArtifacts,
        limits: QwenMLXDiagnosticLimits = .benchmark
    ) {
        self.identifier = verifiedArtifacts.manifest.repositoryID
        self.artifacts = verifiedArtifacts
        self.limits = limits
        self.generator = MLXQwenGenerator(artifacts: verifiedArtifacts)
    }

    init(
        verifiedArtifacts: QwenMLXVerifiedArtifacts,
        limits: QwenMLXDiagnosticLimits = .benchmark,
        generator: any QwenMLXGenerating
    ) {
        self.identifier = verifiedArtifacts.manifest.repositoryID
        self.artifacts = verifiedArtifacts
        self.limits = limits
        self.generator = generator
    }

    public func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability {
        guard
            !sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .unavailable(.unsupportedLanguagePair)
        }

        return artifacts.requiredFilesArePresent()
            ? .available
            : .unavailable(.notInstalled)
    }

    public func translate(
        _ request: TranslationRequest
    ) async throws -> String {
        guard let sourceText = request.sourceText else {
            throw TranslationEngineFailure.invalidRequest
        }
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationEngineFailure.invalidRequest
        }
        guard sourceText.utf8.count <= limits.maxSourceUTF8Bytes else {
            throw TranslationEngineFailure.invalidRequest
        }

        let promptByteCount =
            request.prompt.instructions.utf8.count
            + request.prompt.untrustedInput.utf8.count
        guard promptByteCount <= limits.maxPromptUTF8Bytes else {
            throw TranslationEngineFailure.invalidRequest
        }

        guard artifacts.requiredFilesArePresent() else {
            throw TranslationEngineFailure.unavailable
        }
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        do {
            let output = try await generator.generate(
                request: request,
                limits: limits
            )
            guard !Task.isCancelled else {
                throw TranslationEngineFailure.cancelled
            }
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationEngineFailure.permanent
            }
            return output
        } catch let failure as TranslationEngineFailure {
            throw failure
        } catch is CancellationError {
            throw TranslationEngineFailure.cancelled
        } catch {
            throw TranslationEngineFailure.transient
        }
    }
}

private actor MLXQwenGenerator: QwenMLXGenerating {
    private let artifacts: QwenMLXVerifiedArtifacts
    private var modelContainer: ModelContainer?

    init(artifacts: QwenMLXVerifiedArtifacts) {
        self.artifacts = artifacts
    }

    func generate(
        request: TranslationRequest,
        limits: QwenMLXDiagnosticLimits
    ) async throws -> String {
        let container = try await loadContainer()
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        // A new session is created for every translation. ChatSession retains
        // transcript/KV state, so never reuse a session across benchmark cases
        // or chats.
        let session = ChatSession(
            container,
            instructions: request.prompt.instructions,
            generateParameters: GenerateParameters(
                maxTokens: limits.maxGeneratedTokens,
                temperature: 0
            ),
            additionalContext: ["enable_thinking": false]
        )

        var output = ""
        do {
            for try await chunk in session.streamResponse(
                to: request.prompt.untrustedInput
            ) {
                guard !Task.isCancelled else {
                    throw TranslationEngineFailure.cancelled
                }
                output += chunk
            }
        } catch let failure as TranslationEngineFailure {
            throw failure
        } catch is CancellationError {
            throw TranslationEngineFailure.cancelled
        } catch {
            throw TranslationEngineFailure.transient
        }

        return output
    }

    private func loadContainer() async throws -> ModelContainer {
        if let modelContainer {
            return modelContainer
        }
        guard artifacts.requiredFilesArePresent() else {
            throw TranslationEngineFailure.unavailable
        }
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        do {
            // This overload accepts only a local directory and tokenizer
            // loader. It cannot fall back to a remote model identifier or
            // downloader, which keeps acquisition outside inference.
            let container = try await LLMModelFactory.shared.loadContainer(
                from: artifacts.directory,
                using: #huggingFaceTokenizerLoader()
            )
            guard !Task.isCancelled else {
                throw TranslationEngineFailure.cancelled
            }
            modelContainer = container
            return container
        } catch let failure as TranslationEngineFailure {
            throw failure
        } catch is CancellationError {
            throw TranslationEngineFailure.cancelled
        } catch {
            // The directory was already verified. Configuration, tokenizer,
            // quantization, or weight-loading failures are deterministic for
            // this snapshot and should not silently route around bad artifacts.
            throw TranslationEngineFailure.permanent
        }
    }
}
