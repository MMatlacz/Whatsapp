import Darwin
import Foundation
import QwenMLXDiagnosticAdapter
import TranslationCore

@main
struct QwenMLXBenchmarkCommand {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            let verified = try QwenMLXArtifactVerifier.verify(
                directory: options.modelDirectory
            )
            let limits = QwenMLXDiagnosticLimits.benchmark
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
}

private struct Options {
    enum Corpus: String {
        case functional
        case sharedP01 = "shared-p01"
    }

    let modelDirectory: URL
    let outputDirectory: URL
    let sourceRevision: String?
    let timeoutSeconds: Int
    let corpus: Corpus
    let executionEnvironment: String

    static let usage = """
    Usage:
      qwen-mlx-benchmark --model-dir PATH --output-dir PATH [--corpus functional|shared-p01]
        [--execution-environment NAME] [--source-revision SHA] [--timeout-seconds N]

    The command always runs a one-case real-inference smoke test before the selected
    corpus. It never downloads model artifacts and does not make a translation-quality
    or physical-device acceptance decision. The functional corpus is synthetic and
    includes context-free and bounded-context Indonesian -> Polish comparisons.
    """

    init(arguments: [String]) throws {
        var modelDirectory: URL?
        var outputDirectory: URL?
        var sourceRevision: String?
        var timeoutSeconds = 120
        var corpus = Corpus.sharedP01
        var executionEnvironment = "not-specified"
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
            case "--help", "-h":
                print(Self.usage)
                Darwin.exit(EXIT_SUCCESS)
            default:
                throw CommandError.unknownArgument(argument)
            }
            index += 1
        }

        guard let modelDirectory else {
            throw CommandError.missingArgument("--model-dir")
        }
        guard let outputDirectory else {
            throw CommandError.missingArgument("--output-dir")
        }

        self.modelDirectory = modelDirectory.standardizedFileURL
        self.outputDirectory = outputDirectory.standardizedFileURL
        self.sourceRevision = sourceRevision
        self.timeoutSeconds = timeoutSeconds
        self.corpus = corpus
        self.executionEnvironment = executionEnvironment
    }
}

private enum CommandError: Error, CustomStringConvertible {
    case missingArgument(String)
    case missingValue(String)
    case unknownArgument(String)
    case invalidTimeout
    case invalidCorpus
    case invalidExecutionEnvironment
    case smokeDidNotProduceARecord
    case smokeFailed
    case benchmarkFailed(Int)

    var description: String {
        switch self {
        case .missingArgument(let argument):
            "missing required argument \(argument)"
        case .missingValue(let argument):
            "missing value for \(argument)"
        case .unknownArgument(let argument):
            "unknown argument \(argument)"
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
        }
    }
}
