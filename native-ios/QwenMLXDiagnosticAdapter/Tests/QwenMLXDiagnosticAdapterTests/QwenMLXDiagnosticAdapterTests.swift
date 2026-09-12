import Foundation
import TranslationCore
import XCTest

@testable import QwenMLXDiagnosticAdapter

final class QwenMLXDiagnosticAdapterTests: XCTestCase {
    func testProductionManifestPinsModelProvenance() {
        let manifest = QwenMLXArtifactManifest.qwen3_0_6B_4Bit

        XCTAssertEqual(manifest.repositoryID, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertEqual(
            manifest.revision,
            "73e3e38d981303bc594367cd910ea6eb48349da8"
        )
        XCTAssertEqual(manifest.tokenizerRevision, manifest.revision)
        XCTAssertEqual(manifest.chatTemplateRevision, manifest.revision)
        XCTAssertEqual(manifest.quantization, "4-bit, group_size=64")

        let weights = manifest.artifacts.first {
            $0.path == "model.safetensors"
        }
        XCTAssertEqual(weights?.exactByteCount, 335_450_584)
        XCTAssertEqual(
            weights?.sha256,
            "392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2"
        )
    }

    func testFunctionalCIUsesPublishedQwenNonThinkingSamplingDefaults() {
        let limits = QwenMLXDiagnosticLimits.functionalCI
        XCTAssertEqual(limits.generationTemperature, 0.7)
        XCTAssertEqual(limits.generationTopP, 0.8)
        XCTAssertEqual(limits.generationTopK, 20)
        XCTAssertFalse(limits.thinkingEnabled)

        let settings = QwenMLXGenerationSettings(limits: limits)
        XCTAssertEqual(settings.topP, 0.8)
        XCTAssertEqual(settings.topK, 20)
    }

    func testVerifierAcceptsCompleteMatchingFixture() throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }

        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory,
            manifest: fixture.manifest
        )

        XCTAssertEqual(
            verified.directory,
            fixture.directory.standardizedFileURL
        )
        XCTAssertTrue(verified.requiredFilesArePresent())
    }

    func testVerifierRejectsMissingArtifact() throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(
            at: fixture.directory.appendingPathComponent("config.json")
        )

        XCTAssertThrowsError(
            try QwenMLXArtifactVerifier.verify(
                directory: fixture.directory,
                manifest: fixture.manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? QwenMLXArtifactVerificationError,
                .missingFile("config.json")
            )
        }
    }

    func testVerifierRejectsUnexpectedWeightSize() throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        try Data("wrong-size".utf8).write(
            to: fixture.directory.appendingPathComponent("model.safetensors")
        )

        XCTAssertThrowsError(
            try QwenMLXArtifactVerifier.verify(
                directory: fixture.directory,
                manifest: fixture.manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? QwenMLXArtifactVerificationError,
                .unexpectedFileSize(
                    path: "model.safetensors",
                    expected: 7,
                    actual: 10
                )
            )
        }
    }

    func testVerifierRejectsChecksumMismatch() throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let manifest = QwenMLXArtifactManifest(
            repositoryID: "fixture/model",
            revision: "fixture-revision",
            tokenizerRevision: "fixture-revision",
            chatTemplateRevision: "fixture-revision",
            quantization: "fixture",
            artifacts: [
                .init(path: "config.json"),
                .init(
                    path: "model.safetensors",
                    exactByteCount: 7,
                    sha256: String(repeating: "0", count: 64)
                ),
            ]
        )

        XCTAssertThrowsError(
            try QwenMLXArtifactVerifier.verify(
                directory: fixture.directory,
                manifest: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? QwenMLXArtifactVerificationError,
                .checksumMismatch(
                    path: "model.safetensors",
                    expected: String(repeating: "0", count: 64),
                    actual: "9a129038d9a00aed0cf6a7ea059ca50a813449061ab87848cf1a13eafdf33b2c"
                )
            )
        }
    }

    func testDiagnosticModelForwardsCompleteRequestToGenerator() async throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory,
            manifest: fixture.manifest
        )
        let generator = RecordingGenerator(output: "Ona dołączy później.")
        let model = QwenMLXDiagnosticModel(
            verifiedArtifacts: verified,
            generator: generator
        )
        let request = try makeContextualRequest()

        let output = try await model.translate(request)

        XCTAssertEqual(output, "Ona dołączy później.")
        let captured = await generator.requests()
        XCTAssertEqual(captured, [request])
        XCTAssertTrue(
            captured.first?.prompt.instructions.contains("Indonesian (id)") == true
        )
        XCTAssertTrue(
            captured.first?.prompt.instructions.contains("Polish (pl)") == true
        )
        XCTAssertTrue(
            captured.first?.prompt.untrustedInput.contains("P2") == true
        )
        XCTAssertTrue(
            captured.first?.prompt.untrustedInput.contains("Nanti aku nyusul.") == true
        )
    }

    func testBenchmarkGenerationPreservesRawOutputAndMetrics() async throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory,
            manifest: fixture.manifest
        )
        let metrics = QwenMLXGenerationMetrics(
            modelLoadWasCold: true,
            modelLoadSeconds: 1.25,
            firstTokenSecondsAfterModelReady: 0.4,
            generationSeconds: 0.8,
            promptTokenCount: 42,
            generatedTokenCount: 8,
            tokensPerSecond: 10,
            finishReason: "stop",
            reachedGenerationLimit: false
        )
        let generator = RecordingGenerator(output: "", metrics: metrics)
        let model = QwenMLXDiagnosticModel(
            verifiedArtifacts: verified,
            generator: generator
        )
        let request = try makeContextualRequest()

        let benchmark = try await model.benchmarkGenerate(request)

        XCTAssertEqual(benchmark.output, "")
        XCTAssertEqual(benchmark.metrics, metrics)

        do {
            _ = try await model.translate(request)
            XCTFail("Expected production model contract to reject empty output")
        } catch let failure as TranslationEngineFailure {
            XCTAssertEqual(failure, .permanent)
        }
    }

    func testBenchmarkRejectsCancelledOutputAtAndBelowTokenCap() async throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory, manifest: fixture.manifest
        )
        for count in [12, 96] {
            let model = QwenMLXDiagnosticModel(
                verifiedArtifacts: verified,
                limits: .functionalCI,
                generator: RecordingGenerator(
                    output: "Urwany tekst",
                    metrics: QwenMLXGenerationMetrics(
                        generatedTokenCount: count,
                        finishReason: "cancelled",
                        reachedGenerationLimit: false
                    )
                )
            )
            let executor = QwenMLXBenchmarkExecutor(model: model, limits: .functionalCI)
            let benchmarkFixture = QwenFunctionalTranslationBenchmarkFixtures.fixtures[0]
            let runner = try XCTUnwrap(TranslationBenchmarkRunner(executor: executor, timeoutSeconds: 5))
            let records = await runner.run(fixtures: [benchmarkFixture])
            let record = try XCTUnwrap(records.first)
            XCTAssertEqual(record.output, "Urwany tekst")
            XCTAssertEqual(record.finishReason, "cancelled")
            XCTAssertEqual(record.generatedTokenCount, count)
            XCTAssertEqual(record.termination, count == 96 ? .returned : .cancelled)
            XCTAssertEqual(record.outputValidity, count == 96 ? .truncated : .interrupted)
        }
    }

    func testDiagnosticModelRejectsMissingSourceBeforeGeneration() async throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory,
            manifest: fixture.manifest
        )
        let generator = RecordingGenerator(output: "unused")
        let model = QwenMLXDiagnosticModel(
            verifiedArtifacts: verified,
            generator: generator
        )
        let request = try makeContextualRequest(sourceText: nil)

        do {
            _ = try await model.translate(request)
            XCTFail("Expected invalidRequest")
        } catch let failure as TranslationEngineFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        let requests = await generator.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDiagnosticModelFailsClosedWhenArtifactsDisappear() async throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory,
            manifest: fixture.manifest
        )
        let generator = RecordingGenerator(output: "unused")
        let model = QwenMLXDiagnosticModel(
            verifiedArtifacts: verified,
            generator: generator
        )
        try FileManager.default.removeItem(
            at: fixture.directory.appendingPathComponent("model.safetensors")
        )

        let availability = await model.availability(
            sourceLanguage: "id",
            targetLanguage: "pl"
        )
        XCTAssertEqual(availability, .unavailable(.notInstalled))

        do {
            _ = try await model.translate(try makeContextualRequest())
            XCTFail("Expected unavailable")
        } catch let failure as TranslationEngineFailure {
            XCTAssertEqual(failure, .unavailable)
        }
        let requests = await generator.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDiagnosticModelPreservesCancellation() async throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory,
            manifest: fixture.manifest
        )
        let generator = RecordingGenerator(output: "unused")
        let model = QwenMLXDiagnosticModel(
            verifiedArtifacts: verified,
            generator: generator
        )
        let request = try makeContextualRequest()

        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await model.translate(request)
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let failure as TranslationEngineFailure {
            XCTAssertEqual(failure, .cancelled)
        }
        let requests = await generator.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeContextualRequest(
        sourceText: String? = "Dia nanti nyusul."
    ) throws -> TranslationRequest {
        let alias1 = try XCTUnwrap(TranslationSpeakerAlias(rawValue: "P1"))
        let alias2 = try XCTUnwrap(TranslationSpeakerAlias(rawValue: "P2"))
        let summary = try XCTUnwrap(
            TranslationContextSummary(
                version: 1,
                body: "Rina is delayed at work and plans to join later.",
                sourceMessageCount: 3
            )
        )
        let context = TranslationContext(
            target: TranslationTarget(
                speaker: alias2,
                body: "Dia nanti nyusul."
            ),
            recentTurns: [
                TranslationContextTurn(
                    speaker: alias1,
                    body: "Rina masih di kantor."
                ),
            ],
            quotedTurn: TranslationQuotedTurn(
                speaker: alias2,
                body: "Nanti aku nyusul."
            ),
            summary: summary
        )
        let prompt = try TranslationPromptBuilder().build(
            sourceLanguage: "id",
            targetLanguage: "pl",
            context: context
        )
        let requestID = try XCTUnwrap(
            TranslationRequestID(rawValue: "diagnostic-request")
        )
        let languages = try XCTUnwrap(
            TranslationLanguagePair(
                sourceLanguage: "id",
                targetLanguage: "pl"
            )
        )

        return try XCTUnwrap(
            TranslationRequest(
                id: requestID,
                revision: 1,
                languages: languages,
                prompt: prompt,
                sourceText: sourceText
            )
        )
    }

    private func makeArtifactFixture() throws -> ArtifactFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(#"{"model_type":"qwen3"}"#.utf8).write(
            to: directory.appendingPathComponent("config.json")
        )
        try Data("weights".utf8).write(
            to: directory.appendingPathComponent("model.safetensors")
        )

        let manifest = QwenMLXArtifactManifest(
            repositoryID: "fixture/model",
            revision: "fixture-revision",
            tokenizerRevision: "fixture-revision",
            chatTemplateRevision: "fixture-revision",
            quantization: "fixture",
            artifacts: [
                .init(path: "config.json"),
                .init(
                    path: "model.safetensors",
                    exactByteCount: 7,
                    sha256: "9a129038d9a00aed0cf6a7ea059ca50a813449061ab87848cf1a13eafdf33b2c"
                ),
            ]
        )

        return ArtifactFixture(
            directory: directory,
            manifest: manifest
        )
    }
}

private struct ArtifactFixture {
    let directory: URL
    let manifest: QwenMLXArtifactManifest

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor RecordingGenerator: QwenMLXGenerating {
    private let result: QwenMLXGenerationResult
    private var capturedRequests: [TranslationRequest] = []

    init(
        output: String,
        metrics: QwenMLXGenerationMetrics = .unmeasured
    ) {
        self.result = QwenMLXGenerationResult(
            output: output,
            metrics: metrics
        )
    }

    func generate(
        request: TranslationRequest,
        limits: QwenMLXDiagnosticLimits
    ) async throws -> QwenMLXGenerationResult {
        capturedRequests.append(request)
        return result
    }

    func requests() -> [TranslationRequest] {
        capturedRequests
    }
}
