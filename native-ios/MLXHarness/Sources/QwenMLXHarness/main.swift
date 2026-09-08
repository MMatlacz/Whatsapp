import Darwin
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

private struct HarnessOptions {
    static let defaultModelID = "mlx-community/Qwen3-0.6B-4bit"

    var modelID = defaultModelID
    var prompt = "Reply with exactly: MLX Swift is working."
    var systemPrompt: String?
    var maxTokens = 128
    var temperature: Double = 0.0

    static func parse(_ arguments: [String]) throws -> HarnessOptions {
        var options = HarnessOptions()
        var positionalPromptParts: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--model":
                options.modelID = try value(after: argument, at: &index, in: arguments)
            case "--prompt":
                options.prompt = try value(after: argument, at: &index, in: arguments)
            case "--system":
                options.systemPrompt = try value(after: argument, at: &index, in: arguments)
            case "--max-tokens":
                let rawValue = try value(after: argument, at: &index, in: arguments)
                guard let value = Int(rawValue), value > 0 else {
                    throw HarnessError.invalidValue(argument, rawValue)
                }
                options.maxTokens = value
            case "--temperature":
                let rawValue = try value(after: argument, at: &index, in: arguments)
                guard let value = Double(rawValue), value >= 0 else {
                    throw HarnessError.invalidValue(argument, rawValue)
                }
                options.temperature = value
            case "--help", "-h":
                throw HarnessError.helpRequested
            default:
                if argument.hasPrefix("-") {
                    throw HarnessError.unknownArgument(argument)
                }
                positionalPromptParts.append(argument)
            }

            index += 1
        }

        if !positionalPromptParts.isEmpty {
            options.prompt = positionalPromptParts.joined(separator: " ")
        }

        return options
    }

    private static func value(
        after option: String,
        at index: inout Int,
        in arguments: [String]
    ) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw HarnessError.missingValue(option)
        }
        return arguments[index]
    }
}

private enum HarnessError: Error, CustomStringConvertible {
    case helpRequested
    case missingValue(String)
    case invalidValue(String, String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .helpRequested:
            return HarnessOptions.usage
        case let .missingValue(option):
            return "Missing value for \(option).\n\n\(HarnessOptions.usage)"
        case let .invalidValue(option, value):
            return "Invalid value '\(value)' for \(option).\n\n\(HarnessOptions.usage)"
        case let .unknownArgument(argument):
            return "Unknown argument '\(argument)'.\n\n\(HarnessOptions.usage)"
        }
    }
}

private extension HarnessOptions {
    static var usage: String {
        """
        Usage:
          QwenMLXHarness [prompt]
          QwenMLXHarness --prompt <text> [options]

        Options:
          --model <repo>         Hugging Face model ID.
                                 Default: \(self.defaultModelID)
          --prompt <text>        Prompt to send to the model.
          --system <text>        Optional system instruction.
          --max-tokens <count>   Maximum generated tokens. Default: 128
          --temperature <value>  Sampling temperature. Default: 0
          --help, -h             Show this help.
        """
    }
}

@main
private struct QwenMLXHarness {
    static func main() async {
        do {
            let options = try HarnessOptions.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch HarnessError.helpRequested {
            write(HarnessOptions.usage + "\n", to: .standardOutput)
        } catch {
            write("error: \(error)\n", to: .standardError)
            Darwin.exit(2)
        }
    }

    private static func run(_ options: HarnessOptions) async throws {
        write("Loading \(options.modelID)…\n", to: .standardError)
        let loadStart = ContinuousClock.now

        let model = try await #huggingFaceLoadModelContainer(
            configuration: ModelConfiguration(id: options.modelID)
        )

        let loadDuration = ContinuousClock.now - loadStart
        write("Loaded in \(loadDuration).\n", to: .standardError)

        let parameters = GenerateParameters(
            maxTokens: options.maxTokens,
            temperature: options.temperature
        )
        let session = ChatSession(
            model,
            instructions: options.systemPrompt,
            generateParameters: parameters
        )

        write("\n--- response ---\n", to: .standardError)
        let generationStart = ContinuousClock.now

        for try await chunk in session.streamResponse(
            to: options.prompt,
            images: [],
            videos: []
        ) {
            write(chunk, to: .standardOutput)
        }

        write("\n", to: .standardOutput)
        let generationDuration = ContinuousClock.now - generationStart
        write("--- done in \(generationDuration) ---\n", to: .standardError)
    }

    private static func write(_ string: String, to handle: FileHandle) {
        handle.write(Data(string.utf8))
    }
}
