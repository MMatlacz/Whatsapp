import Foundation
import TranslationCore

public enum TranslationBenchmarkTermination: String, Codable, Equatable, Sendable {
    case returned
    case failed
    case cancelled
    case timedOut
    case budgetFailed
}

public enum TranslationBenchmarkOutputValidity: String, Codable, Equatable, Sendable {
    case validText
    case emptyText
    case thinkingOnly
    case truncated
    case notProduced
    case unknown
}

public struct TranslationBenchmarkExecution: Equatable, Sendable {
    public let termination: TranslationBenchmarkTermination
    public let output: String?
    public let finishReason: String?
    public let generatedTokenCount: Int?
    public let reachedGenerationLimit: Bool?
    public let errorCategory: String?
    public let errorDescription: String?

    public init(
        termination: TranslationBenchmarkTermination,
        output: String? = nil,
        finishReason: String? = nil,
        generatedTokenCount: Int? = nil,
        reachedGenerationLimit: Bool? = nil,
        errorCategory: String? = nil,
        errorDescription: String? = nil
    ) {
        self.termination = termination
        self.output = output
        self.finishReason = finishReason
        self.generatedTokenCount = generatedTokenCount
        self.reachedGenerationLimit = reachedGenerationLimit
        self.errorCategory = errorCategory
        self.errorDescription = errorDescription
    }
}

public protocol TranslationBenchmarkExecuting: Sendable {
    func execute(_ request: TranslationRequest) async -> TranslationBenchmarkExecution
}

public struct QwenMLXBenchmarkExecutor: TranslationBenchmarkExecuting, Sendable {
    private let model: any MultilingualLocalModel
    private let limits: QwenMLXDiagnosticLimits

    public init(
        model: any MultilingualLocalModel,
        limits: QwenMLXDiagnosticLimits = .benchmark
    ) {
        self.model = model
        self.limits = limits
    }

    public func execute(
        _ request: TranslationRequest
    ) async -> TranslationBenchmarkExecution {
        guard let sourceText = request.sourceText else {
            return failure(.invalidRequest)
        }

        let promptByteCount = request.prompt.instructions.utf8.count
            + request.prompt.untrustedInput.utf8.count
        guard
            sourceText.utf8.count <= limits.maxSourceUTF8Bytes,
            promptByteCount <= limits.maxPromptUTF8Bytes
        else {
            return TranslationBenchmarkExecution(
                termination: .budgetFailed,
                errorCategory: "input-budget",
                errorDescription: "Benchmark input exceeds configured source/prompt byte budget."
            )
        }

        guard !Task.isCancelled else {
            return cancelled()
        }

        do {
            let output = try await model.translate(request)
            return TranslationBenchmarkExecution(
                termination: .returned,
                output: output,
                finishReason: nil,
                generatedTokenCount: nil,
                reachedGenerationLimit: nil
            )
        } catch let engineFailure as TranslationEngineFailure {
            switch engineFailure {
            case .cancelled:
                return cancelled()
            default:
                return failure(engineFailure)
            }
        } catch is CancellationError {
            return cancelled()
        } catch {
            return TranslationBenchmarkExecution(
                termination: .failed,
                errorCategory: "unexpected-error",
                errorDescription: String(describing: error)
            )
        }
    }

    private func failure(
        _ failure: TranslationEngineFailure
    ) -> TranslationBenchmarkExecution {
        TranslationBenchmarkExecution(
            termination: .failed,
            errorCategory: String(describing: failure),
            errorDescription: "TranslationEngineFailure.\(String(describing: failure))"
        )
    }

    private func cancelled() -> TranslationBenchmarkExecution {
        TranslationBenchmarkExecution(
            termination: .cancelled,
            errorCategory: "cancelled",
            errorDescription: "Benchmark execution was cancelled."
        )
    }
}

public struct TranslationBenchmarkModelProvenance: Codable, Equatable, Sendable {
    public let repositoryID: String
    public let revision: String
    public let tokenizerRevision: String
    public let chatTemplateRevision: String
    public let quantization: String

    public init(manifest: QwenMLXArtifactManifest) {
        self.repositoryID = manifest.repositoryID
        self.revision = manifest.revision
        self.tokenizerRevision = manifest.tokenizerRevision
        self.chatTemplateRevision = manifest.chatTemplateRevision
        self.quantization = manifest.quantization
    }
}

public struct TranslationBenchmarkResultRecord: Codable, Equatable, Sendable {
    public let fixtureID: String
    public let title: String
    public let route: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let contextWindow: Int
    public let focus: String
    public let promptVersion: String
    public let termination: TranslationBenchmarkTermination
    public let outputValidity: TranslationBenchmarkOutputValidity
    public let output: String?
    public let finishReason: String?
    public let generatedTokenCount: Int?
    public let errorCategory: String?
    public let errorDescription: String?

    init(
        fixture: TranslationBenchmarkFixture,
        execution: TranslationBenchmarkExecution
    ) {
        self.fixtureID = fixture.id
        self.title = fixture.title
        self.route = fixture.route
        self.sourceLanguage = fixture.request.languages.sourceLanguage
        self.targetLanguage = fixture.request.languages.targetLanguage
        self.contextWindow = fixture.contextWindow
        self.focus = fixture.focus
        self.promptVersion = fixture.request.prompt.version.rawValue
        self.termination = execution.termination
        self.outputValidity = Self.classifyOutput(execution)
        self.output = execution.output
        self.finishReason = execution.finishReason
        self.generatedTokenCount = execution.generatedTokenCount
        self.errorCategory = execution.errorCategory
        self.errorDescription = execution.errorDescription
    }

    private static func classifyOutput(
        _ execution: TranslationBenchmarkExecution
    ) -> TranslationBenchmarkOutputValidity {
        guard execution.termination == .returned else {
            return .notProduced
        }
        guard let output = execution.output else {
            return .unknown
        }
        if execution.reachedGenerationLimit == true {
            return .truncated
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .emptyText
        }
        if thinkingOnly(trimmed) {
            return .thinkingOnly
        }
        return .validText
    }

    private static func thinkingOnly(_ output: String) -> Bool {
        let lowercased = output.lowercased()
        guard lowercased.hasPrefix("<think>") else {
            return false
        }
        guard let closingRange = lowercased.range(of: "</think>") else {
            return true
        }
        let remainder = output[closingRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty
    }
}

public struct TranslationBenchmarkReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timestamp: String
    public let sourceRevision: String?
    public let model: TranslationBenchmarkModelProvenance
    public let maxGeneratedTokens: Int
    public let results: [TranslationBenchmarkResultRecord]

    public init(
        timestamp: String,
        sourceRevision: String?,
        model: TranslationBenchmarkModelProvenance,
        maxGeneratedTokens: Int,
        results: [TranslationBenchmarkResultRecord]
    ) {
        self.schemaVersion = 1
        self.timestamp = timestamp
        self.sourceRevision = sourceRevision
        self.model = model
        self.maxGeneratedTokens = maxGeneratedTokens
        self.results = results
    }
}

public struct TranslationBenchmarkRunner: Sendable {
    private let executor: any TranslationBenchmarkExecuting
    private let timeoutNanoseconds: UInt64

    public init?(
        executor: any TranslationBenchmarkExecuting,
        timeoutSeconds: Int
    ) {
        guard timeoutSeconds > 0 else { return nil }
        self.executor = executor
        self.timeoutNanoseconds = UInt64(timeoutSeconds) * 1_000_000_000
    }

    public func run(
        fixtures: [TranslationBenchmarkFixture]
    ) async -> [TranslationBenchmarkResultRecord] {
        var records: [TranslationBenchmarkResultRecord] = []
        records.reserveCapacity(fixtures.count)

        for fixture in fixtures {
            guard !Task.isCancelled else {
                break
            }
            let execution = await executeWithTimeout(fixture.request)
            records.append(
                TranslationBenchmarkResultRecord(
                    fixture: fixture,
                    execution: execution
                )
            )
        }

        return records
    }

    private func executeWithTimeout(
        _ request: TranslationRequest
    ) async -> TranslationBenchmarkExecution {
        await withTaskGroup(
            of: TranslationBenchmarkExecution.self,
            returning: TranslationBenchmarkExecution.self
        ) { group in
            group.addTask {
                await executor.execute(request)
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return TranslationBenchmarkExecution(
                        termination: .cancelled,
                        errorCategory: "cancelled",
                        errorDescription: "Benchmark timeout task was cancelled."
                    )
                }
                return TranslationBenchmarkExecution(
                    termination: .timedOut,
                    errorCategory: "timeout",
                    errorDescription: "Benchmark case exceeded its configured timeout."
                )
            }

            let first = await group.next() ?? TranslationBenchmarkExecution(
                termination: .failed,
                errorCategory: "runner-error",
                errorDescription: "Benchmark task group produced no result."
            )
            group.cancelAll()
            return first
        }
    }
}

public enum TranslationBenchmarkExporter {
    public static func encodeResult(
        _ result: TranslationBenchmarkResultRecord
    ) throws -> Data {
        let encoder = makeEncoder()
        return try encoder.encode(result)
    }

    public static func encodeReport(
        _ report: TranslationBenchmarkReport
    ) throws -> Data {
        let encoder = makeEncoder()
        return try encoder.encode(report)
    }

    public static func markdownSummary(
        _ report: TranslationBenchmarkReport
    ) -> String {
        let sourceRevision = report.sourceRevision ?? "unknown"
        var lines = [
            "# Local translation benchmark",
            "",
            "- Timestamp: \(report.timestamp)",
            "- Source revision: \(sourceRevision)",
            "- Model: \(report.model.repositoryID)",
            "- Model revision: \(report.model.revision)",
            "- Tokenizer revision: \(report.model.tokenizerRevision)",
            "- Chat-template revision: \(report.model.chatTemplateRevision)",
            "- Quantization: \(report.model.quantization)",
            "- Max generated tokens: \(report.maxGeneratedTokens)",
            "",
            "| Fixture | Route | Context | Execution | Output validity | Finish reason | Tokens |",
            "| --- | --- | ---: | --- | --- | --- | ---: |",
        ]

        for result in report.results {
            let finishReason = sanitize(result.finishReason ?? "unknown")
            let tokenCount = result.generatedTokenCount.map(String.init) ?? "unknown"
            lines.append(
                "| \(sanitize(result.fixtureID)) | \(sanitize(result.route)) | \(result.contextWindow) | \(result.termination.rawValue) | \(result.outputValidity.rawValue) | \(finishReason) | \(tokenCount) |"
            )
        }

        lines.append("")
        lines.append("Execution success, output validity, and translation quality are separate outcomes. A non-empty result is not automatically a quality pass.")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func write(
        report: TranslationBenchmarkReport,
        to outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = outputDirectory.standardizedFileURL
        let resultsDirectory = directory.appendingPathComponent(
            "results",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: resultsDirectory,
            withIntermediateDirectories: true
        )

        try encodeReport(report).write(
            to: directory.appendingPathComponent("report.json"),
            options: .atomic
        )
        try Data(markdownSummary(report).utf8).write(
            to: directory.appendingPathComponent("summary.md"),
            options: .atomic
        )

        for result in report.results {
            try encodeResult(result).write(
                to: resultsDirectory.appendingPathComponent(
                    "\(result.fixtureID).json"
                ),
                options: .atomic
            )
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
