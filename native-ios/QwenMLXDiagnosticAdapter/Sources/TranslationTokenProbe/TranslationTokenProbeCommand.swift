import Foundation
import QwenMLXDiagnosticAdapter

@main
struct TranslationTokenProbeCommand {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5 else {
            print("Usage: translation-token-probe MODEL_DIR INPUT_JSON OUTPUT_JSON SOURCE_SHA")
            return
        }
        try await TranslationTokenProbe.run(
            modelDirectory: URL(fileURLWithPath: args[1]),
            inputFile: URL(fileURLWithPath: args[2]),
            outputFile: URL(fileURLWithPath: args[3]), sourceRevision: args[4]
        )
    }
}
