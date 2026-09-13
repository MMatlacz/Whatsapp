import Foundation
import QwenMLXDiagnosticAdapter

@main
struct TranslateGemmaQualityProbeCommand {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3 || args.count == 4 else {
            print("Usage: translategemma-quality-probe MODEL_DIR CORPUS_JSON OUTPUT_JSON [LIMIT]")
            return
        }
        let limit = args.count == 4 ? Int(args[3]) ?? -1 : 36
        try await TranslateGemmaQualityProbe.run(
            modelDirectory: URL(fileURLWithPath: args[0]),
            corpusURL: URL(fileURLWithPath: args[1]),
            outputURL: URL(fileURLWithPath: args[2]),
            limit: limit
        )
    }
}
