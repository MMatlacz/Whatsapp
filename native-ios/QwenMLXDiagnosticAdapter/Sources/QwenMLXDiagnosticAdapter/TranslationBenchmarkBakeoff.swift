import Foundation
import TranslationCore

/// Runs the same fixture list against multiple locally provisioned MLX model
/// folders. Provisioning and verification stay outside this runner; no network
/// access or model download is possible here.
public struct TranslationBenchmarkBakeoffRunner: Sendable {
    private let limits: QwenMLXDiagnosticLimits
    private let timeoutSeconds: Int

    public init(
        limits: QwenMLXDiagnosticLimits = .functionalCI,
        timeoutSeconds: Int = 120
    ) {
        self.limits = limits
        self.timeoutSeconds = timeoutSeconds
    }

    public func run(
        inputs: [TranslationBenchmarkCandidateInput],
        fixtures: [TranslationBenchmarkFixture],
        timestamp: String,
        sourceRevision: String?,
        executionEnvironment: String,
        corpus: String = "qwen-functional"
    ) async -> TranslationBenchmarkBakeoffReport {
        var runs: [TranslationBenchmarkCandidateRun] = []
        runs.reserveCapacity(inputs.count)

        for input in inputs {
            do {
                let verified = try QwenMLXArtifactVerifier.verify(
                    directory: input.directory,
                    candidate: input.candidate
                )
                guard let runner = TranslationBenchmarkRunner(
                    executor: QwenMLXBenchmarkExecutor(
                        model: QwenMLXDiagnosticModel(
                            verifiedArtifacts: verified,
                            limits: limits
                        ),
                        limits: limits
                    ),
                    timeoutSeconds: timeoutSeconds
                ) else {
                    runs.append(
                        TranslationBenchmarkCandidateRun(
                            candidate: input.candidate,
                            status: .failed,
                            errorCategory: "invalid-timeout",
                            errorDescription: "Timeout must be a positive integer."
                        )
                    )
                    continue
                }

                let results = await runner.run(fixtures: fixtures)
                let report = TranslationBenchmarkReport(
                    timestamp: timestamp,
                    sourceRevision: sourceRevision,
                    model: TranslationBenchmarkModelProvenance(
                        manifest: verified.manifest,
                        generation: QwenMLXGenerationSettings(limits: limits),
                        executionEnvironment: executionEnvironment,
                        candidate: input.candidate
                    ),
                    maxGeneratedTokens: limits.maxGeneratedTokens,
                    results: results,
                    corpus: corpus,
                    timeoutSeconds: timeoutSeconds,
                    resourceMetrics: TranslationBenchmarkResourceMetrics.captureProcessHighWater()
                )
                let isComplete = results.count == fixtures.count
                runs.append(
                    TranslationBenchmarkCandidateRun(
                        candidate: input.candidate,
                        status: isComplete ? .completed : .failed,
                        report: report,
                        errorCategory: isComplete ? nil : "incomplete-run",
                        errorDescription: isComplete
                            ? nil
                            : "Benchmark returned \(results.count) of \(fixtures.count) fixture records."
                    )
                )
            } catch {
                let localized = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                runs.append(
                    TranslationBenchmarkCandidateRun(
                        candidate: input.candidate,
                        status: .failed,
                        errorCategory: "provisioning-or-inference",
                        errorDescription: localized
                    )
                )
            }
        }

        return TranslationBenchmarkBakeoffReport(
            timestamp: timestamp,
            sourceRevision: sourceRevision,
            corpus: corpus,
            fixtureIDs: fixtures.map(\.id),
            candidates: runs
        )
    }
}

public enum TranslationBenchmarkBakeoffExporter {
    public static func encode(
        _ report: TranslationBenchmarkBakeoffReport
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    public static func markdownSummary(
        _ report: TranslationBenchmarkBakeoffReport
    ) -> String {
        var lines = [
            "# Multilingual local-model candidate bake-off",
            "",
            "- Timestamp: \(report.timestamp)",
            "- Source revision: \(report.sourceRevision ?? "unknown")",
            "- Corpus: \(report.corpus)",
            "- Fixtures: \(report.fixtureIDs.count)",
            "",
            "| Candidate | Repository | Provenance | Run status | Cases | Returned | Valid text | Mean first token s | Mean generation s | Mean tok/s | Peak RSS bytes | Quality review |",
            "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]

        for run in report.candidates {
            guard let candidateReport = run.report else {
                lines.append(
                    "| \(sanitize(run.candidate.displayName)) | \(sanitize(run.candidate.repositoryID)) | \(run.candidate.provenance.rawValue) | failed | 0 | 0 | 0 | unknown | unknown | unknown | unknown | failed: \(sanitize(run.errorDescription ?? "unknown")) |"
                )
                continue
            }

            let results = candidateReport.results
            let returned = results.filter { $0.termination == .returned }.count
            let valid = results.filter { $0.outputValidity == .validText }.count
            let firstToken = mean(results.compactMap(\.firstTokenSecondsAfterModelReady))
            let generation = mean(results.compactMap(\.generationSeconds))
            let rate = mean(results.compactMap(\.tokensPerSecond))
            let peak = candidateReport.resourceMetrics?.peakResidentMemoryBytes
                .map(String.init) ?? "unknown"
            let status = run.status.rawValue
            let review = run.status == .completed
                ? "unreviewed"
                : "failed: \(sanitize(run.errorDescription ?? "incomplete run"))"
            lines.append(
                "| \(sanitize(run.candidate.displayName)) | \(sanitize(run.candidate.repositoryID)) | \(run.candidate.provenance.rawValue) | \(status) | \(results.count) | \(returned) | \(valid) | \(format(firstToken)) | \(format(generation)) | \(format(rate)) | \(peak) | \(review) |"
            )
        }

        lines.append(contentsOf: [
            "",
            "## Per-fixture review matrix",
            "",
            "The raw output remains in each candidate report. This compact matrix is for human review of meaning, hallucination, Polish fluency, tone/preservation, and context benefit.",
            "",
            "| Fixture | " + report.candidates.map { sanitize($0.candidate.id.rawValue) }.joined(separator: " | ") + " |",
            "| --- | " + report.candidates.map { _ in "---" }.joined(separator: " | ") + " |",
        ])

        for fixtureID in report.fixtureIDs {
            var cells = [sanitize(fixtureID)]
            for run in report.candidates {
                guard let result = run.report?.results.first(where: { $0.fixtureID == fixtureID }) else {
                    cells.append(sanitize(run.errorDescription ?? "not run"))
                    continue
                }
                let output = result.output?.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = output?.isEmpty == false ? output! : result.outputValidity.rawValue
                cells.append(sanitize(value))
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }

        lines.append(contentsOf: [
            "",
            "## Review gates",
            "",
            "- Quality is intentionally `unreviewed` until every output is scored against the predeclared meaning, hallucination, Polish fluency, tone/preservation, and context-benefit rubric.",
            "- A returned or non-empty answer is not a translation-quality pass.",
            "- Peak RSS is a process high-water measurement; isolate candidates in separate processes before using memory as an acceptance gate.",
            "- Candidate metadata marked `researchUnpinned` does not establish exact snapshot provenance or redistribution approval.",
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    public static func write(
        report: TranslationBenchmarkBakeoffReport,
        to outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = outputDirectory.standardizedFileURL
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(report).write(
            to: directory.appendingPathComponent("bakeoff.json"),
            options: .atomic
        )
        try Data(markdownSummary(report).utf8).write(
            to: directory.appendingPathComponent("summary.md"),
            options: .atomic
        )

        let candidatesDirectory = directory.appendingPathComponent(
            "candidates",
            isDirectory: true
        )
        for run in report.candidates {
            guard let candidateReport = run.report else { continue }
            let candidateDirectory = candidatesDirectory.appendingPathComponent(
                run.candidate.id.rawValue,
                isDirectory: true
            )
            try TranslationBenchmarkExporter.write(
                report: candidateReport,
                to: candidateDirectory,
                fileManager: fileManager
            )
        }
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return String(format: "%.3f", value)
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
