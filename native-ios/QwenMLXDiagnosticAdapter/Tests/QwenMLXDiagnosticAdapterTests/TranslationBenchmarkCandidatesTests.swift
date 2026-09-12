import Foundation
import TranslationCore
import XCTest

@testable import QwenMLXDiagnosticAdapter

final class TranslationBenchmarkCandidatesTests: XCTestCase {
    func testCatalogUsesTheP02d3PriorityOrderAndMemoryBudget() {
        XCTAssertEqual(
            TranslationBenchmarkCandidate.catalog.map(\.id),
            [
                .gemma3_1BItQat4Bit,
                .qwen3_5_0_8B4Bit,
                .gemma3_270MIt4Bit,
            ]
        )
        XCTAssertEqual(
            TranslationBenchmarkCandidate.catalog.map(\.memoryBudgetBytes),
            Array(repeating: 1_610_612_736, count: 3)
        )
        XCTAssertEqual(
            TranslationBenchmarkCandidate.catalog.map(\.provenance),
            Array(repeating: .researchUnpinned, count: 3)
        )
        XCTAssertEqual(
            TranslationBenchmarkCandidate.catalog.map(\.repositoryID),
            [
                "mlx-community/gemma-3-1b-it-qat-4bit",
                "mlx-community/Qwen3.5-0.8B-MLX-4bit",
                "mlx-community/gemma-3-270m-it-4bit",
            ]
        )
    }

    func testCandidateResolverAcceptsCanonicalIDsAndShortAliases() {
        XCTAssertEqual(
            TranslationBenchmarkCandidate.resolve("gemma-3-1b-it-qat-4bit")?.id,
            .gemma3_1BItQat4Bit
        )
        XCTAssertEqual(
            TranslationBenchmarkCandidate.resolve("QWEN35")?.id,
            .qwen3_5_0_8B4Bit
        )
        XCTAssertEqual(
            TranslationBenchmarkCandidate.resolve(
                "mlx-community/Qwen3.5-0.8B-MLX-4bit"
            )?.id,
            .qwen3_5_0_8B4Bit
        )
        XCTAssertEqual(
            TranslationBenchmarkCandidate.resolve(" gemma270m ")?.id,
            .gemma3_270MIt4Bit
        )
        XCTAssertNil(TranslationBenchmarkCandidate.resolve("unknown-model"))
    }

    func testOperatorRevisionIsCarriedWithoutPretendingTheCandidateIsPinned() {
        let candidate = TranslationBenchmarkCandidate.candidate(for: .qwen3_5_0_8B4Bit)
        let revised = candidate.withSnapshotRevision("abc123")

        XCTAssertEqual(revised?.revision, "abc123")
        XCTAssertEqual(revised?.tokenizerRevision, "abc123")
        XCTAssertEqual(revised?.chatTemplateRevision, "abc123")
        XCTAssertEqual(revised?.provenance, .researchUnpinned)
        XCTAssertFalse(revised?.isPinned ?? true)
        XCTAssertNil(candidate.withSnapshotRevision("   "))
    }

    func testCandidateVerifierAcceptsCommonMLXFolderShapeWithoutInventingPin() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"model_type":"gemma3"}"#.utf8).write(
            to: directory.appendingPathComponent("config.json")
        )
        try Data("weights".utf8).write(
            to: directory.appendingPathComponent("model.safetensors")
        )
        try Data("tokenizer".utf8).write(
            to: directory.appendingPathComponent("tokenizer.model")
        )

        let candidate = TranslationBenchmarkCandidate.candidate(for: .gemma3_1BItQat4Bit)
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: directory,
            candidate: candidate
        )

        XCTAssertTrue(verified.requiredFilesArePresent())
        XCTAssertEqual(verified.manifest.repositoryID, candidate.repositoryID)
        XCTAssertEqual(verified.manifest.revision, "unresolved-local-snapshot")
        XCTAssertEqual(
            verified.manifest.artifacts.map(\.path),
            ["config.json", "model.safetensors", "tokenizer.model"]
        )
    }

    func testCandidateVerifierFailsClosedWhenTokenizerIsMissing() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        try Data("weights".utf8).write(
            to: directory.appendingPathComponent("model.safetensors")
        )

        XCTAssertThrowsError(
            try QwenMLXArtifactVerifier.verify(
                directory: directory,
                candidate: .candidate(for: .qwen3_5_0_8B4Bit)
            )
        ) { error in
            XCTAssertEqual(
                error as? QwenMLXArtifactVerificationError,
                .missingFile("tokenizer.json (or tokenizer.model/spiece.model)")
            )
        }
    }

    func testBakeoffExporterKeepsFailedCandidatesVisibleAndLeavesQualityUnreviewed() throws {
        let candidate = TranslationBenchmarkCandidate.candidate(for: .gemma3_270MIt4Bit)
        let report = TranslationBenchmarkBakeoffReport(
            timestamp: "2026-09-12T00:00:00Z",
            sourceRevision: "abc123",
            corpus: "qwen-functional",
            fixtureIDs: ["fixture-1"],
            candidates: [
                TranslationBenchmarkCandidateRun(
                    candidate: candidate,
                    status: .failed,
                    errorCategory: "provisioning",
                    errorDescription: "missing tokenizer"
                ),
            ]
        )

        let summary = TranslationBenchmarkBakeoffExporter.markdownSummary(report)

        XCTAssertTrue(summary.contains("Gemma 3 270M IT 4-bit"))
        XCTAssertTrue(summary.contains("failed: missing tokenizer"))
        XCTAssertTrue(summary.contains("Quality review"))
        XCTAssertTrue(summary.contains("researchUnpinned"))
        XCTAssertTrue(summary.contains("unreviewed"))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
