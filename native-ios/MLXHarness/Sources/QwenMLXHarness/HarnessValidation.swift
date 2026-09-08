import Foundation

struct HarnessOptions {
    static let defaultModelID = "mlx-community/Qwen3-0.6B-4bit"

    var modelID = defaultModelID
    var prompt = "Reply with exactly: MLX Swift is working."
    var systemPrompt: String?
    var maxTokens = 128
    var temperature: Float = 0.0

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
                guard let value = Float(rawValue), value.isFinite, value >= 0 else {
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

enum HarnessError: Error, Equatable, CustomStringConvertible {
    case helpRequested
    case missingValue(String)
    case invalidValue(String, String)
    case unknownArgument(String)
    case emptyResponse

    var description: String {
        switch self {
        case .emptyResponse:
            return "Model generated no non-whitespace text."
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

extension HarnessOptions {
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
          --temperature <value>  Finite, nonnegative sampling temperature. Default: 0
          --help, -h             Show this help.
        """
    }
}

/// Tracks whether streamed output contains text without retaining the response.
struct ResponseValidator {
    private var hasText = false

    mutating func observe(_ chunk: String) {
        if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasText = true
        }
    }

    func validate() throws {
        guard hasText else {
            throw HarnessError.emptyResponse
        }
    }
}
