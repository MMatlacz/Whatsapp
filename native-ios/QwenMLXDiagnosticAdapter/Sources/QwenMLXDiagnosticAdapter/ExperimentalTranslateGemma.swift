import CryptoKit
import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Explicit experimental local inference. Never writes prompts or outputs to disk.
public actor ExperimentalTranslateGemma {
    public enum Failure: Error { case invalidInput, integrity, busy, incomplete }
    private struct Manifest: Decodable {
        struct Model: Decodable {
            struct Artifact: Decodable { let path: String; let bytes: Int; let sha256: String }
            let repository: String
            let revision: String
            let artifacts: [Artifact]
        }
        let model: Model
    }
    private let directory: URL
    private let manifestURL: URL
    private var container: ModelContainer?
    private var running = false

    public init(directory: URL, manifestURL: URL) {
        self.directory = directory
        self.manifestURL = manifestURL
    }

    public func translate(
        _ text: String,
        comment: String,
        vocabularyHints: [TranslateGemmaVocabularyHint] = []
    ) async throws -> String {
        guard !running else { throw Failure.busy }
        let prompt: TranslateGemmaPrompt
        do {
            prompt = try TranslateGemmaPrompt(
                targetText: text,
                guidance: comment,
                vocabularyHints: vocabularyHints
            )
        } catch {
            throw Failure.invalidInput
        }
        running = true
        defer { running = false }
        if container == nil {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)).model
            guard manifest.repository == "mlx-community/translategemma-4b-it-4bit",
                  manifest.revision == "5788ec08c047f3f2e17808101b8d9566ac930d58",
                  !manifest.artifacts.isEmpty,
                  Set(manifest.artifacts.map(\.path)).isSuperset(of: ["config.json", "tokenizer.json", "model.safetensors"]),
                  manifest.artifacts.allSatisfy({ $0.bytes >= 0 && !$0.sha256.isEmpty }) else {
                throw Failure.integrity
            }
            for artifact in manifest.artifacts {
                guard !artifact.path.isEmpty,
                      !artifact.path.contains("/"),
                      artifact.path != ".",
                      artifact.path != ".." else { throw Failure.integrity }
                let handle = try FileHandle(forReadingFrom: directory.appendingPathComponent(artifact.path))
                defer { try? handle.close() }
                var hash = SHA256()
                var size = 0
                while true {
                    try Task.checkCancellation()
                    let count = try autoreleasepool {
                        guard let bytes = try handle.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty else { return 0 }
                        hash.update(data: bytes)
                        return bytes.count
                    }
                    if count == 0 { break }
                    size += count
                }
                guard size == artifact.bytes,
                      hash.finalize().map({ String(format: "%02x", $0) }).joined() == artifact.sha256 else {
                    throw Failure.integrity
                }
            }
            let loaded = try await LLMModelFactory.shared.loadContainer(from: directory, using: #huggingFaceTokenizerLoader())
            await loaded.update {
                $0.configuration.extraEOSTokens.insert("<end_of_turn>")
                $0.configuration.eosTokenIds.formUnion([1, 106])
            }
            container = loaded
        }
        guard let container else { throw Failure.integrity }
        // Use TranslateGemma's own chat template and content metadata. This
        // matches the measured diagnostic baseline and avoids an adapter-local
        // hand-built turn that could silently drift from the model contract.
        let tokens = try await container.perform { context in
            try context.tokenizer.applyChatTemplate(
                messages: [prompt.modelMessage],
                tools: nil,
                additionalContext: nil
            )
        }
        guard !tokens.isEmpty, tokens.count <= 2048 else { throw Failure.invalidInput }
        var output = ""
        var completed = false
        for await event in try await container.generate(
            input: LMInput(tokens: MLXArray(tokens)), parameters: GenerateParameters(maxTokens: 512, temperature: 0)
        ) {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text): output += text
            case .info(let info):
                switch info.stopReason {
                case .stop:
                    completed = true
                case .length, .cancelled:
                    completed = false
                @unknown default:
                    completed = false
                }
            case .toolCall: throw Failure.incomplete
            @unknown default: throw Failure.incomplete
            }
        }
        let decision = TranslationQualityGate.evaluate(
            sourceText: text,
            output: output,
            termination: completed ? .returned : .failed,
            finishReason: completed ? "stop" : "incomplete"
        )
        guard completed,
              decision.status == .requiresHumanReview else {
            throw Failure.incomplete
        }
        return output
    }
}
