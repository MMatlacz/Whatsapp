import Foundation
import TranslationCore
import XCTest

@testable import QwenMLXDiagnosticAdapter

final class TranslationBenchmarkTests: XCTestCase {
    func testSharedP01CorpusPreservesUnencodedFixtureIdentityAndWindows() throws {
        let fixtures = P01SharedTranslationBenchmarkFixtures.unencoded

        XCTAssertEqual(
            fixtures.map(\.id),
            [
                "id-en-hard-particles",
                "en-pl-natural-chat",
                "id-pl-omitted-subject",
                "contextual-id-pl-0",
                "contextual-id-pl-3",
                "contextual-id-pl-8",
                "contextual-id-pl-16",
            ]
        )
        XCTAssertEqual(fixtures.map(\.contextWindow), [0, 0, 0, 0, 3, 8, 16])
        XCTAssertEqual(
            fixtures.filter { $0.id.hasPrefix("contextual-id-pl-") }
                .map { $0.request.sourceText },
            Array(
                repeating: "\"Nanti aku nyusul\" kata dia. Jangan panik dong, traffic lagi gila nih wkwk. Bapak sudah tahu kalau Tante mau ikut juga?",
                count: 4
            )
        )
        XCTAssertTrue(
            fixtures.allSatisfy {
                $0.request.prompt.version
                    == TranslationPromptBuilder.currentVersion
            }
        )

        let contextual16 = try XCTUnwrap(
            fixtures.first { $0.id == "contextual-id-pl-16" }
        )
        XCTAssertTrue(
            contextual16.request.prompt.untrustedInput.contains(
                "Nanti aku nyusul."
            )
        )
        XCTAssertTrue(
            contextual16.request.prompt.untrustedInput.contains(
                "Does 'nyusul' mean she will come later?"
            )
        )
    }

    func testRunnerSeparatesExecutionAndOutputValidity() async throws {
        let fixtures = Array(
            P01SharedTranslationBenchmarkFixtures.unencoded.prefix(4)
        )
        let executor = SequenceExecutor(
            executions: [
                TranslationBenchmarkExecution(
                    termination: .returned,
                    output: "Ona dołączy później."
                ),
                TranslationBenchmarkExecution(
                    termination: .returned,
                    output: "   \n"
                ),
                TranslationBenchmarkExecution(
                    termination: .returned,
                    output: "<think>analiza bez odpowiedzi</think>"
                ),
                TranslationBenchmarkExecution(
                    termination: .returned,
                    output: "Urwany tekst",
                    finishReason: "length",
                    generatedTokenCount: 512,
                    reachedGenerationLimit: true
                ),
            ]
        )
        let runner = try XCTUnwrap(
            TranslationBenchmarkRunner(
                executor: executor,
                timeoutSeconds: 5
            )
        )

        let records = await runner.run(fixtures: fixtures)

        XCTAssertEqual(
            records.map(\.termination),
            Array(repeating: .returned, count: 4)
        )
        XCTAssertEqual(
            records.map(\.outputValidity),
            [.validText, .emptyText, .thinkingOnly, .truncated]
        )
        XCTAssertEqual(records[3].finishReason, "length")
        XCTAssertEqual(records[3].generatedTokenCount, 512)
    }

    func testRunnerClassifiesTimeoutWithoutWaitingForExecutorCompletion() async throws {
        let executor = SlowExecutor(delayNanoseconds: 2_000_000_000)
        let runner = try XCTUnwrap(
            TranslationBenchmarkRunner(
                executor: executor,
                timeoutSeconds: 1
            )
        )
        let fixture = try XCTUnwrap(
            P01SharedTranslationBenchmarkFixtures.unencoded.first
        )

        let records = await runner.run(fixtures: [fixture])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].termination, .timedOut)
        XCTAssertEqual(records[0].outputValidity, .notProduced)
        XCTAssertEqual(records[0].errorCategory, "timeout")
    }

    func testExporterWritesDeterministicReviewableArtifacts() throws {
        let fixture = try XCTUnwrap(
            P01SharedTranslationBenchmarkFixtures.unencoded.first
        )
        let record = TranslationBenchmarkResultRecord(
            fixture: fixture,
            execution: TranslationBenchmarkExecution(
                termination: .returned,
                output: "Powiedziała, że może później."
            )
        )
        let report = TranslationBenchmarkReport(
            timestamp: "2026-09-09T10:00:00Z",
            sourceRevision: "abc123",
            model: TranslationBenchmarkModelProvenance(
                manifest: .qwen3_0_6B_4Bit
            ),
            maxGeneratedTokens: 512,
            results: [record]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try TranslationBenchmarkExporter.write(
            report: report,
            to: directory
        )

        let reportData = try Data(
            contentsOf: directory.appendingPathComponent("report.json")
        )
        let individualData = try Data(
            contentsOf: directory
                .appendingPathComponent("results", isDirectory: true)
                .appendingPathComponent("id-en-hard-particles.json")
        )
        let summary = try String(
            contentsOf: directory.appendingPathComponent("summary.md"),
            encoding: .utf8
        )

        XCTAssertEqual(
            reportData,
            try TranslationBenchmarkExporter.encodeReport(report)
        )
        XCTAssertEqual(
            individualData,
            try TranslationBenchmarkExporter.encodeResult(record)
        )
        XCTAssertTrue(summary.contains("Execution success, output validity, and translation quality are separate outcomes."))
        XCTAssertTrue(summary.contains("unknown"))
    }
}

private actor SequenceExecutor: TranslationBenchmarkExecuting {
    private var executions: [TranslationBenchmarkExecution]

    init(executions: [TranslationBenchmarkExecution]) {
        self.executions = executions
    }

    func execute(
        _ request: TranslationRequest
    ) async -> TranslationBenchmarkExecution {
        guard !executions.isEmpty else {
            return TranslationBenchmarkExecution(
                termination: .failed,
                errorCategory: "test-exhausted"
            )
        }
        return executions.removeFirst()
    }
}

private struct SlowExecutor: TranslationBenchmarkExecuting {
    let delayNanoseconds: UInt64

    func execute(
        _ request: TranslationRequest
    ) async -> TranslationBenchmarkExecution {
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return TranslationBenchmarkExecution(
                termination: .cancelled,
                errorCategory: "cancelled"
            )
        }
        return TranslationBenchmarkExecution(
            termination: .returned,
            output: "late"
        )
    }
}
