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
    public let generationTemperature: Double
    public let generationTopP: Double
    public let generationTopK: Int
    public let thinkingEnabled: Bool

    public init?(
        maxGeneratedTokens: Int,
        maxSourceUTF8Bytes: Int,
        maxPromptUTF8Bytes: Int,
        generationTemperature: Double = 0,
        generationTopP: Double = 1,
        generationTopK: Int = 0,
        thinkingEnabled: Bool = false
    ) {
        guard
            maxGeneratedTokens > 0,
            maxSourceUTF8Bytes > 0,
            maxPromptUTF8Bytes > 0,
            generationTemperature.isFinite,
            generationTemperature >= 0,
            generationTopP.isFinite,
            generationTopP > 0,
            generationTopP <= 1,
            generationTopK >= 0
        else {
            return nil
        }

        self.maxGeneratedTokens = maxGeneratedTokens
        self.maxSourceUTF8Bytes = maxSourceUTF8Bytes
        self.maxPromptUTF8Bytes = maxPromptUTF8Bytes
        self.generationTemperature = generationTemperature
        self.generationTopP = generationTopP
        self.generationTopK = generationTopK
        self.thinkingEnabled = thinkingEnabled
    }

    public static let benchmark = QwenMLXDiagnosticLimits(
        maxGeneratedTokens: 512,
        maxSourceUTF8Bytes: 16 * 1_024,
        maxPromptUTF8Bytes: 256 * 1_024
    )!

    public static let functionalCI = QwenMLXDiagnosticLimits(
        maxGeneratedTokens: 96,
        maxSourceUTF8Bytes: 16 * 1_024,
        maxPromptUTF8Bytes: 256 * 1_024,
        generationTemperature: 0.7,
        generationTopP: 0.8,
        generationTopK: 20,
        thinkingEnabled: false
    )!
}

public struct QwenMLXGenerationSettings: Codable, Equatable, Sendable {
    public let maxGeneratedTokens: Int
    public let temperature: Double
    public let topP: Double
    public let topK: Int
    public let thinkingEnabled: Bool

    public init(limits: QwenMLXDiagnosticLimits) {
        self.maxGeneratedTokens = limits.maxGeneratedTokens
        self.temperature = limits.generationTemperature
        self.topP = limits.generationTopP
        self.topK = limits.generationTopK
        self.thinkingEnabled = limits.thinkingEnabled
    }
}

public struct QwenMLXRuntimeProvenance: Codable, Equatable, Sendable {
    public let runtime: String
    public let runtimeVersion: String
    public let runtimeRevision: String
    public let mlxSwiftVersion: String
    public let mlxSwiftRevision: String
    public let swiftHuggingFaceVersion: String
    public let swiftHuggingFaceRevision: String
    public let swiftTransformersVersion: String
    public let swiftTransformersRevision: String

    public init(
        runtime: String,
        runtimeVersion: String,
        runtimeRevision: String,
        mlxSwiftVersion: String,
        mlxSwiftRevision: String,
        swiftHuggingFaceVersion: String,
        swiftHuggingFaceRevision: String,
        swiftTransformersVersion: String,
        swiftTransformersRevision: String
    ) {
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.runtimeRevision = runtimeRevision
        self.mlxSwiftVersion = mlxSwiftVersion
        self.mlxSwiftRevision = mlxSwiftRevision
        self.swiftHuggingFaceVersion = swiftHuggingFaceVersion
        self.swiftHuggingFaceRevision = swiftHuggingFaceRevision
        self.swiftTransformersVersion = swiftTransformersVersion
        self.swiftTransformersRevision = swiftTransformersRevision
    }

    public static let pinned = QwenMLXRuntimeProvenance(
        runtime: "mlx-swift-lm",
        runtimeVersion: "3.31.3",
        runtimeRevision: "1c05248bb0899e2a7a4962b84d319cf12f4e12aa",
        mlxSwiftVersion: "0.31.6",
        mlxSwiftRevision: "0bb916c67f4b9e5c682cbe02a42c701c93ab5021",
        swiftHuggingFaceVersion: "0.10.1",
        swiftHuggingFaceRevision: "b5403ed09403f674601fd1123e07c5b32914d16f",
        swiftTransformersVersion: "1.3.4",
        swiftTransformersRevision: "c21fdcde390313a6d98d8e33a346f2c3486c3ab0"
    )
}

public struct QwenMLXGenerationMetrics: Equatable, Sendable {
    public let modelLoadWasCold: Bool?
    public let modelLoadSeconds: TimeInterval?
    public let firstTokenSecondsAfterModelReady: TimeInterval?
    public let generationSeconds: TimeInterval?
    public let promptTokenCount: Int?
    public let generatedTokenCount: Int?
    public let tokensPerSecond: Double?
    public let finishReason: String?
    public let reachedGenerationLimit: Bool?

    public init(
        modelLoadWasCold: Bool? = nil,
        modelLoadSeconds: TimeInterval? = nil,
        firstTokenSecondsAfterModelReady: TimeInterval? = nil,
        generationSeconds: TimeInterval? = nil,
        promptTokenCount: Int? = nil,
        generatedTokenCount: Int? = nil,
        tokensPerSecond: Double? = nil,
        finishReason: String? = nil,
        reachedGenerationLimit: Bool? = nil
    ) {
        self.modelLoadWasCold = modelLoadWasCold
        self.modelLoadSeconds = modelLoadSeconds
        self.firstTokenSecondsAfterModelReady = firstTokenSecondsAfterModelReady
        self.generationSeconds = generationSeconds
        self.promptTokenCount = promptTokenCount
        self.generatedTokenCount = generatedTokenCount
        self.tokensPerSecond = tokensPerSecond
        self.finishReason = finishReason
        self.reachedGenerationLimit = reachedGenerationLimit
    }

    public static let unmeasured = QwenMLXGenerationMetrics()
}

public struct QwenMLXGenerationResult: Equatable, Sendable {
    public let output: String
    public let metrics: QwenMLXGenerationMetrics

    public init(
        output: String,
        metrics: QwenMLXGenerationMetrics = .unmeasured
    ) {
        self.output = output
        self.metrics = metrics
    }
}

protocol QwenMLXGenerating: Sendable {
    func generate(
        request: TranslationRequest,
        limits: QwenMLXDiagnosticLimits
    ) async throws -> QwenMLXGenerationResult
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
        let result = try await benchmarkGenerate(request)
        guard !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationEngineFailure.permanent
        }
        return result.output
    }

    func benchmarkGenerate(
        _ request: TranslationRequest
    ) async throws -> QwenMLXGenerationResult {
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
            let result = try await generator.generate(
                request: request,
                limits: limits
            )
            guard !Task.isCancelled else {
                throw TranslationEngineFailure.cancelled
            }
            return result
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
    ) async throws -> QwenMLXGenerationResult {
        let loaded = try await loadContainerMeasured()
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        // A new session is created for every translation. ChatSession retains
        // transcript/KV state, so never reuse a session across benchmark cases
        // or chats.
        let session = ChatSession(
            loaded.container,
            instructions: request.prompt.instructions,
            generateParameters: GenerateParameters(
                maxTokens: limits.maxGeneratedTokens,
                temperature: Float(limits.generationTemperature),
                topP: Float(limits.generationTopP),
                topK: limits.generationTopK
            ),
            additionalContext: ["enable_thinking": limits.thinkingEnabled]
        )

        var output = ""
        var completionInfo: GenerateCompletionInfo?
        do {
            for try await generation in session.streamDetails(
                to: request.prompt.untrustedInput,
                images: [],
                videos: []
            ) {
                guard !Task.isCancelled else {
                    throw TranslationEngineFailure.cancelled
                }

                switch generation {
                case .chunk(let chunk):
                    output += chunk
                case .info(let info):
                    completionInfo = info
                case .toolCall:
                    // No tools are configured for translation. Treat a tool call
                    // as an invalid diagnostic generation rather than silently
                    // dropping model output.
                    throw TranslationEngineFailure.permanent
                @unknown default:
                    throw TranslationEngineFailure.permanent
                }
            }
        } catch let failure as TranslationEngineFailure {
            throw failure
        } catch is CancellationError {
            throw TranslationEngineFailure.cancelled
        } catch {
            throw TranslationEngineFailure.transient
        }

        let completionMetrics = completionInfo.map(Self.metrics(from:))
        let metrics = QwenMLXGenerationMetrics(
            modelLoadWasCold: loaded.wasCold,
            modelLoadSeconds: loaded.loadSeconds,
            firstTokenSecondsAfterModelReady: completionMetrics?.firstTokenSecondsAfterModelReady,
            generationSeconds: completionMetrics?.generationSeconds,
            promptTokenCount: completionMetrics?.promptTokenCount,
            generatedTokenCount: completionMetrics?.generatedTokenCount,
            tokensPerSecond: completionMetrics?.tokensPerSecond,
            finishReason: completionMetrics?.finishReason,
            reachedGenerationLimit: completionMetrics?.reachedGenerationLimit
        )

        return QwenMLXGenerationResult(
            output: output,
            metrics: metrics
        )
    }

    private func loadContainerMeasured() async throws -> (
        container: ModelContainer,
        wasCold: Bool,
        loadSeconds: TimeInterval
    ) {
        if let modelContainer {
            return (modelContainer, false, 0)
        }
        guard artifacts.requiredFilesArePresent() else {
            throw TranslationEngineFailure.unavailable
        }
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
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
            let elapsed = max(
                0,
                ProcessInfo.processInfo.systemUptime - startedAt
            )
            return (container, true, elapsed)
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

    private static func metrics(
        from info: GenerateCompletionInfo
    ) -> QwenMLXGenerationMetrics {
        let stop = normalizedStopReason(info.stopReason)
        let rate = info.tokensPerSecond
        return QwenMLXGenerationMetrics(
            firstTokenSecondsAfterModelReady: info.promptTime,
            generationSeconds: info.generateTime,
            promptTokenCount: info.promptTokenCount,
            generatedTokenCount: info.generationTokenCount,
            tokensPerSecond: rate.isFinite ? rate : nil,
            finishReason: stop.reason,
            reachedGenerationLimit: stop.reachedGenerationLimit
        )
    }

    private static func normalizedStopReason(
        _ reason: GenerateStopReason
    ) -> (reason: String, reachedGenerationLimit: Bool) {
        switch reason {
        case .stop:
            ("stop", false)
        case .length:
            ("length", true)
        case .cancelled:
            ("cancelled", false)
        @unknown default:
            ("unknown", false)
        }
    }
}
