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

            let results = await runner.run(
                fixtures: P01SharedTranslationBenchmarkFixtures.unencoded
            )
            let report = TranslationBenchmarkReport(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                sourceRevision: options.sourceRevision,
                model: TranslationBenchmarkModelProvenance(
                    manifest: verified.manifest
                ),
                maxGeneratedTokens: limits.maxGeneratedTokens,
                results: results
            )
            try TranslationBenchmarkExporter.write(
                report: report,
                to: options.outputDirectory
            )

            print(TranslationBenchmarkExporter.markdownSummary(report))
            print("Wrote benchmark artifacts to \(options.outputDirectory.path)")
        } catch {
            let message = "qwen-mlx-benchmark: \(error)\n\n\(Options.usage)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

private struct Options {
    let modelDirectory: URL
    let outputDirectory: URL
    let sourceRevision: String?
    let timeoutSeconds: Int

    static let usage = """
    Usage:
      qwen-mlx-benchmark --model-dir PATH --output-dir PATH [--source-revision SHA] [--timeout-seconds N]

    The command uses the source-controlled unencoded P0.1 fixture corpus, including
    context windows 0/3/8/16. It never downloads model artifacts and does not make
    a translation-quality or physical-device acceptance decision.
    """

    init(arguments: [String]) throws {
        var modelDirectory: URL?
        var outputDirectory: URL?
        var sourceRevision: String?
        var timeoutSeconds = 120
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
                Foundation.exit(EXIT_SUCCESS)
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
    }
}

private enum CommandError: Error, CustomStringConvertible {
    case missingArgument(String)
    case missingValue(String)
    case unknownArgument(String)
    case invalidTimeout

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
        }
    }
}
