import CryptoKit
import Darwin
import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Diagnostic replay only. Input token IDs come from an archived synthetic
/// Python run; this does not validate Swift chat-template/tokenizer parity.
public enum TranslationTokenProbe {
    private struct Input: Decodable {
        struct Model: Decodable {
            struct Artifact: Decodable {
                let path: String
                let bytes: Int
                let sha256: String
            }
            let repository: String
            let revision: String
            let artifacts: [Artifact]
        }
        struct Row: Decodable {
            let fixtureID: String
            let actualInput: String
            let inputTokenIDs: [Int]
        }
        let model: Model
        let results: [Row]
    }

    public static func run(
        modelDirectory: URL, inputFile: URL, outputFile: URL,
        sourceRevision: String, limit: Int = 2
    ) async throws {
        let inputData = try Data(contentsOf: inputFile)
        let input = try JSONDecoder().decode(Input.self, from: inputData)
        guard input.model.repository == "mlx-community/translategemma-4b-it-4bit",
              input.model.revision == "5788ec08c047f3f2e17808101b8d9566ac930d58",
              limit > 0, !input.results.isEmpty,
              Set(input.model.artifacts.map(\.path)).isSuperset(of: ["config.json", "tokenizer.json"]),
              input.model.artifacts.contains(where: { $0.path.hasSuffix(".safetensors") }),
              input.results.allSatisfy({ row in
                  !row.inputTokenIDs.isEmpty && row.inputTokenIDs.count <= 2048
                      && row.inputTokenIDs.allSatisfy { (0..<262208).contains($0) }
              }) else {
            throw ProbeError.invalidInput
        }
        for artifact in input.model.artifacts {
            guard !artifact.path.contains("/"), artifact.path != ".." else {
                throw ProbeError.invalidInput
            }
            let url = modelDirectory.appendingPathComponent(artifact.path)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            var size = 0
            while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
                size += chunk.count
            }
            guard size == artifact.bytes,
                  hex(hash.finalize()) == artifact.sha256 else {
                throw ProbeError.integrityFailure
            }
        }
        #if targetEnvironment(simulator)
        let environment = "ios-simulator"
        #elseif os(iOS)
        let environment = "ios-device"
        #else
        let environment = "macos"
        #endif
        var report: [String: Any] = [
            "status": "loading", "sourceRevision": sourceRevision,
            "inputSHA256": hex(SHA256.hash(data: inputData)),
            "repository": input.model.repository, "revision": input.model.revision,
            "executionEnvironment": environment,
            "inputMode": "archived-token-replay-not-native-tokenizer-validation",
            "productionRouting": false, "maxNewTokens": 512,
            "temperature": 0, "stopTokenIDs": [1, 106],
            "baselinePeakRSSBytes": peakRSS(), "results": [[String: Any]](),
        ]
        try write(report, to: outputFile)
        let started = ProcessInfo.processInfo.systemUptime
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: #huggingFaceTokenizerLoader()
        )
        await container.update { context in
            context.configuration.extraEOSTokens.insert("<end_of_turn>")
            context.configuration.eosTokenIds.formUnion([1, 106])
        }
        report["loadSeconds"] = ProcessInfo.processInfo.systemUptime - started
        report["status"] = "running"
        try write(report, to: outputFile)
        var results = [[String: Any]]()
        for row in input.results.prefix(limit) {
            guard !row.inputTokenIDs.isEmpty, row.inputTokenIDs.count <= 2048 else {
                throw ProbeError.invalidInput
            }
            let start = ProcessInfo.processInfo.systemUptime
            var text = ""
            var metrics: [String: Any] = [:]
            var thermalPeak = ProcessInfo.processInfo.thermalState.rawValue
            let prepared = LMInput(tokens: MLXArray(row.inputTokenIDs))
            for await event in try await container.generate(
                input: prepared, parameters: GenerateParameters(maxTokens: 512, temperature: 0)
            ) {
                try Task.checkCancellation()
                thermalPeak = max(thermalPeak, ProcessInfo.processInfo.thermalState.rawValue)
                switch event {
                case .chunk(let chunk): text += chunk
                case .info(let info):
                    metrics = ["generatedTokens": info.generationTokenCount,
                               "stopReason": String(describing: info.stopReason),
                               "hitTokenLimit": info.generationTokenCount >= 512,
                               "promptSeconds": info.promptTime,
                               "generationSeconds": info.generateTime]
                case .toolCall: throw ProbeError.unexpectedTool
                @unknown default: throw ProbeError.invalidInput
                }
            }
            guard !metrics.isEmpty else { throw ProbeError.missingCompletion }
            results.append([
                "fixtureID": row.fixtureID, "actualInput": row.actualInput,
                "inputTokenIDs": row.inputTokenIDs, "output": text, "metrics": metrics,
                "durationSeconds": ProcessInfo.processInfo.systemUptime - start,
                "peakRSSBytes": peakRSS(), "maximumObservedThermalState": thermalPeak,
            ])
            report["results"] = results
            try write(report, to: outputFile)
        }
        report["status"] = "completed"
        report["peakRSSBytes"] = peakRSS()
        try write(report, to: outputFile)
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func peakRSS() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        return Int64(usage.ru_maxrss)
    }

    private static func write(_ value: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }

    enum ProbeError: Error, Equatable { case invalidInput, integrityFailure, unexpectedTool, missingCompletion }
}
