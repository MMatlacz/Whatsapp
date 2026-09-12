import Darwin
import Foundation
import QwenMLXDiagnosticAdapter
import TranslationCore

@main
struct QwenMLXBenchmarkCommand {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            if !options.candidates.isEmpty {
                try await runBakeoff(options)
                return
            }

            guard let modelDirectory = options.modelDirectory else {
                throw CommandError.missingArgument("--model-dir or --candidate")
            }
            let verified = try QwenMLXArtifactVerifier.verify(
                directory: modelDirectory
            )
            // The CI command is the functional path. Keep its generation
            // settings aligned with the Simulator harness so the fallback
            // cannot silently benchmark a different decoding configuration.
            let limits = QwenMLXDiagnosticLimits.functionalCI
            let model = QwenMLXDiagnosticModel(
                verifiedArtifacts: verified,
                limits: limits
            )
            let executor = QwenMLXBenchmarkExecutor(
                model: model,
                limits: limits
            )
            guard let runner = TranslationBenchmarkRunner(
                executor: executor,
                timeoutSeconds: options.timeoutSeconds
            ) else {
                throw CommandError.invalidTimeout
            }

            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: options.outputDirectory,
                withIntermediateDirectories: true
            )

            let smokeRecords = await runner.run(
                fixtures: [QwenFunctionalTranslationBenchmarkFixtures.smoke]
            )
            guard let smoke = smokeRecords.first else {
                throw CommandError.smokeDidNotProduceARecord
            }
            try TranslationBenchmarkExporter.writeResult(
                smoke,
                to: options.outputDirectory.appendingPathComponent("smoke.json")
            )
            print("Smoke status: \(smokeStatus(smoke))")
            guard isSuccessful(smoke) else {
                throw CommandError.smokeFailed
            }
            if options.smokeOnly {
                return
            }

            let fixtures: [TranslationBenchmarkFixture]
            switch options.corpus {
            case .functional:
                fixtures = QwenFunctionalTranslationBenchmarkFixtures.fixtures
            case .sharedP01:
                fixtures = P01SharedTranslationBenchmarkFixtures.unencoded
            }
            let results = await runner.run(
                fixtures: fixtures
            )
            let report = TranslationBenchmarkReport(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                sourceRevision: options.sourceRevision,
                model: TranslationBenchmarkModelProvenance(
                    manifest: verified.manifest,
                    generation: QwenMLXGenerationSettings(limits: limits),
                    executionEnvironment: options.executionEnvironment
                ),
                maxGeneratedTokens: limits.maxGeneratedTokens,
                results: results,
                corpus: options.corpus.rawValue,
                timeoutSeconds: options.timeoutSeconds
            )
            try TranslationBenchmarkExporter.write(
                report: report,
                to: options.outputDirectory
            )

            print(TranslationBenchmarkExporter.markdownSummary(report))
            print("Wrote benchmark artifacts to \(options.outputDirectory.path)")
            let failed = results.filter { !isSuccessful($0) }
            if !failed.isEmpty {
                throw CommandError.benchmarkFailed(failed.count)
            }
        } catch {
            let message = "qwen-mlx-benchmark: \(error)\n\n\(Options.usage)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func isSuccessful(
        _ result: TranslationBenchmarkResultRecord
    ) -> Bool {
        result.termination == .returned
            && result.outputValidity == .validText
            && !(result.output ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private static func smokeStatus(
        _ result: TranslationBenchmarkResultRecord
    ) -> String {
        isSuccessful(result) ? "passed" : "failed"
    }

    private static func runBakeoff(_ options: Options) async throws {
        let fixtures: [TranslationBenchmarkFixture]
        switch options.corpus {
        case .functional:
            fixtures = options.smokeOnly
                ? [QwenFunctionalTranslationBenchmarkFixtures.smoke]
                : QwenFunctionalTranslationBenchmarkFixtures.fixtures
        case .sharedP01:
            fixtures = options.smokeOnly
                ? [P01SharedTranslationBenchmarkFixtures.unencoded[0]]
                : P01SharedTranslationBenchmarkFixtures.unencoded
        }

        let report = await TranslationBenchmarkBakeoffRunner(
            limits: .functionalCI,
            timeoutSeconds: options.timeoutSeconds
        ).run(
            inputs: options.candidates,
            fixtures: fixtures,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sourceRevision: options.sourceRevision,
            executionEnvironment: options.executionEnvironment,
            corpus: options.corpus.rawValue
        )
        try TranslationBenchmarkBakeoffExporter.write(
            report: report,
            to: options.outputDirectory
        )

        print(TranslationBenchmarkBakeoffExporter.markdownSummary(report))
        print("Wrote candidate bake-off artifacts to \(options.outputDirectory.path)")

        let failedRuns = report.candidates.filter { run in
            guard let candidateReport = run.report else { return true }
            return run.status != .completed
                || candidateReport.results.contains { !isSuccessful($0) }
        }
        if !failedRuns.isEmpty {
            throw CommandError.bakeoffFailed(failedRuns.count)
        }
    }
}

private struct Options {
    enum Corpus: String {
        case functional
        case sharedP01 = "shared-p01"
    }

    let modelDirectory: URL?
    let candidates: [TranslationBenchmarkCandidateInput]
    let outputDirectory: URL
    let sourceRevision: String?
    let timeoutSeconds: Int
    let corpus: Corpus
    let executionEnvironment: String
    let smokeOnly: Bool

    static let usage = """
    Usage:
      qwen-mlx-benchmark --model-dir PATH --output-dir PATH [--corpus functional|shared-p01]
        [--execution-environment NAME] [--source-revision SHA] [--timeout-seconds N] [--smoke-only]

      qwen-mlx-benchmark --candidate ID[@REVISION]=PATH --candidate ID[@REVISION]=PATH ... --output-dir PATH
        [--corpus functional|shared-p01] [--execution-environment NAME]
        [--source-revision SHA] [--timeout-seconds N] [--smoke-only]

    The single-model --model-dir command runs a one-case real-inference smoke test
    before its selected corpus. The multi-candidate command runs the full selected
    corpus for every candidate. Neither path downloads model artifacts or makes a
    translation-quality or physical-device acceptance decision. The functional
    corpus is synthetic and includes context-free and bounded-context Indonesian ->
    Polish comparisons.
    Candidate folders are verified locally and are never downloaded by this command.
    Candidate metadata is research-level until an exact snapshot revision and
    integrity record are captured by the operator.
    """

    init(arguments: [String]) throws {
        var modelDirectory: URL?
        var candidates: [TranslationBenchmarkCandidateInput] = []
        var outputDirectory: URL?
        var sourceRevision: String?
        var timeoutSeconds = 120
        var corpus = Corpus.sharedP01
        var corpusWasSpecified = false
        var executionEnvironment = "not-specified"
        var smokeOnly = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--model-dir":
                index += 1
                guard index < arguments.count else {
                    throw CommandError.missingValue(argument)
                }
                modelDirectory = URL(fileURLWithPath: arguments[index])
            case "--candidate":
                index += 1
                guard index < arguments.count else {
                    throw CommandError.missingValue(argument)
                }
                let value = arguments[index]
                guard
                    let separator = value.firstIndex(of: "="),
                    separator != value.startIndex
                else {
                    throw CommandError.invalidCandidate(value)
                }
                let candidateSpec = String(value[..<separator])
                let pathStart = value.index(after: separator)
                let path = String(value[pathStart...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let candidateParts = candidateSpec.split(separator: "@", maxSplits: 1)
                guard let candidateName = candidateParts.first else {
                    throw CommandError.invalidCandidate(value)
                }
                guard var candidate = TranslationBenchmarkCandidate.resolve(String(candidateName)) else {
                    throw CommandError.invalidCandidate(value)
                }
                if candidateParts.count == 2 {
                    guard let withRevision = candidate.withSnapshotRevision(
                        String(candidateParts[1])
                    ) else {
                        throw CommandError.invalidCandidate(value)
                    }
                    candidate = withRevision
                }
                guard
                    !path.isEmpty,
                    !candidates.contains(where: { $0.candidate.id == candidate.id })
                else {
                    throw CommandError.invalidCandidate(value)
                }
                candidates.append(
                    TranslationBenchmarkCandidateInput(
                        candidate: candidate,
                        directory: URL(fileURLWithPath: path)
                    )
                )
            case "--output-dir":
                index += 1
                guard index < arguments.count else {
                    throw CommandError.missingValue(argument)
                }
                outputDirectory = URL(fileURLWithPath: arguments[index])
            case "--source-revision":
                index += 1
                guard index < arguments.count else {
                    throw CommandError.missingValue(argument)
                }
                let value = arguments[index].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                sourceRevision = value.isEmpty ? nil : value
            case "--corpus":
                index += 1
                guard
                    index < arguments.count,
                    let value = Corpus(rawValue: arguments[index])
                else {
                    throw CommandError.invalidCorpus
                }
                corpus = value
                corpusWasSpecified = true
            case "--execution-environment":
                index += 1
                guard index < arguments.count else {
                    throw CommandError.missingValue(argument)
                }
                let value = arguments[index].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !value.isEmpty else {
                    throw CommandError.invalidExecutionEnvironment
                }
                executionEnvironment = value
            case "--timeout-seconds":
                index += 1
                guard
                    index < arguments.count,
                    let value = Int(arguments[index]),
                    value > 0
                else {
                    throw CommandError.invalidTimeout
                }
                timeoutSeconds = value
            case "--smoke-only":
                smokeOnly = true
            case "--help", "-h":
                print(Self.usage)
                Darwin.exit(EXIT_SUCCESS)
            default:
                throw CommandError.unknownArgument(argument)
            }
            index += 1
        }

        guard modelDirectory != nil || !candidates.isEmpty else {
            throw CommandError.missingArgument("--model-dir or --candidate")
        }
        guard modelDirectory == nil || candidates.isEmpty else {
            throw CommandError.mixedModelArguments
        }
        if !candidates.isEmpty && !corpusWasSpecified {
            corpus = .functional
        }
        guard let outputDirectory else {
            throw CommandError.missingArgument("--output-dir")
        }

        self.modelDirectory = modelDirectory?.standardizedFileURL
        self.candidates = candidates
        self.outputDirectory = outputDirectory.standardizedFileURL
        self.sourceRevision = sourceRevision
        self.timeoutSeconds = timeoutSeconds
        self.corpus = corpus
        self.executionEnvironment = executionEnvironment
        self.smokeOnly = smokeOnly
    }
}

private enum CommandError: Error, CustomStringConvertible {
    case missingArgument(String)
    case missingValue(String)
    case unknownArgument(String)
    case invalidCandidate(String)
    case mixedModelArguments
    case invalidTimeout
    case invalidCorpus
    case invalidExecutionEnvironment
    case smokeDidNotProduceARecord
    case smokeFailed
    case benchmarkFailed(Int)
    case bakeoffFailed(Int)

    var description: String {
        switch self {
        case .missingArgument(let argument):
            "missing required argument \(argument)"
        case .missingValue(let argument):
            "missing value for \(argument)"
        case .unknownArgument(let argument):
            "unknown argument \(argument)"
        case .invalidCandidate(let value):
            "candidate must be a known ID[@REVISION]=PATH pair without duplicates: \(value)"
        case .mixedModelArguments:
            "use --model-dir or one or more --candidate arguments, not both"
        case .invalidTimeout:
            "timeout must be a positive integer number of seconds"
        case .invalidCorpus:
            "corpus must be functional or shared-p01"
        case .invalidExecutionEnvironment:
            "execution environment must not be empty"
        case .smokeDidNotProduceARecord:
            "smoke test did not produce a result record"
        case .smokeFailed:
            "real-inference smoke test failed"
        case .benchmarkFailed(let count):
            "benchmark produced \(count) failed, empty, truncated, or otherwise invalid result(s)"
        case .bakeoffFailed(let count):
            "candidate bake-off produced \(count) failed, empty, truncated, or otherwise invalid candidate run(s)"
        }
    }
}
