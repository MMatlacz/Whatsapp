import Darwin
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

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
        var responseValidator = ResponseValidator()

        for try await chunk in session.streamResponse(
            to: options.prompt,
            images: [],
            videos: []
        ) {
            responseValidator.observe(chunk)
            write(chunk, to: .standardOutput)
        }

        try responseValidator.validate()
        write("\n", to: .standardOutput)
        let generationDuration = ContinuousClock.now - generationStart
        write("--- done in \(generationDuration) ---\n", to: .standardError)
    }

    private static func write(_ string: String, to handle: FileHandle) {
        handle.write(Data(string.utf8))
    }
}
