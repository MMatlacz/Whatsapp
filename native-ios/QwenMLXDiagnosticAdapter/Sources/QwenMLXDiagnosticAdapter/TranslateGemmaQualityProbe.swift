import CryptoKit
import Darwin
import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Offline, research-only comparison of the archived TranslateGemma prompt and
/// the native Swift chat-template prompt. This probe never feeds its output to
/// the application or to a send path.
public enum TranslateGemmaQualityProbe {
    public enum ProbeError: Error, Equatable, Sendable {
        case invalidCorpus
        case invalidModelMetadata
        case invalidArtifactPath
        case artifactMissing(String)
        case artifactIntegrity(String)
        case invalidLimit
        case invalidPrompt(String)
        case missingCompletion(String)
        case unexpectedToolCall
    }

    private struct Corpus: Decodable {
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
            let input: String
            let intendedMeaning: String
            let preservationNotes: String
            let contextMode: String
            let suppliedContext: [String: AnyCodable]
            let actualInput: String
            let inputTokenIDs: [Int]
        }

        let schemaVersion: Int
        let model: Model
        let results: [Row]
    }

    /// Minimal JSON value used only to retain the corpus context fields in
    /// the exported comparison. The probe never interprets context as model
    /// instructions in this source-only comparison.
    private enum AnyCodable: Decodable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: AnyCodable])
        case array([AnyCodable])
        case null

        init(from decoder: Swift.Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode([String: AnyCodable].self) {
                self = .object(value)
            } else if let value = try? container.decode([AnyCodable].self) {
                self = .array(value)
            } else {
                throw Swift.DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported JSON value"
                )
            }
        }
    }

    private struct Generation: Encodable {
        let output: String
        let stopReason: String
        let generatedTokenCount: Int
        let promptTokenCount: Int
        let hitTokenLimit: Bool
        let durationSeconds: Double
    }

    private struct RowReport: Encodable {
        let fixtureID: String
        let input: String
        let intendedMeaning: String
        let preservationNotes: String
        let contextMode: String
        let archivedPromptSHA256: String
        let nativePromptSHA256: String
        let archivedPromptTokenCount: Int
        let nativePromptTokenCount: Int
        let archived: Generation
        let native: Generation
    }

    private struct Report: Encodable {
        let schemaVersion: Int
        var status: String
        let repository: String
        let revision: String
        let sourceCorpusSHA256: String
        let sourceCorpusSchemaVersion: Int
        let modelDirectory: String
        let executionEnvironment: String
        let promptStrategy: String
        let generation: [String: String]
        let qualityReview: String
        let productionRouting: Bool
        var rows: [RowReport]
        var peakRSSBytes: Int64
    }

    /// Run the exact frozen corpus locally. The caller must provide a model
    /// directory from an already provisioned snapshot and the archived corpus
    /// JSON. No network or Hugging Face lookup is performed.
    public static func run(
        modelDirectory: URL,
        corpusURL: URL,
        outputURL: URL,
        limit: Int = 36
    ) async throws {
        guard limit > 0 else { throw ProbeError.invalidLimit }
        let corpusData = try Data(contentsOf: corpusURL)
        let corpus = try JSONDecoder().decode(Corpus.self, from: corpusData)
        guard corpus.schemaVersion == 1,
              corpus.model.repository == "mlx-community/translategemma-4b-it-4bit",
              corpus.model.revision == "5788ec08c047f3f2e17808101b8d9566ac930d58",
              !corpus.results.isEmpty,
              limit <= corpus.results.count else {
            throw ProbeError.invalidCorpus
        }

        try verifyArtifacts(corpus.model.artifacts, in: modelDirectory)

        var report = Report(
            schemaVersion: 1,
            status: "loading",
            repository: corpus.model.repository,
            revision: corpus.model.revision,
            sourceCorpusSHA256: sha256(corpusData),
            sourceCorpusSchemaVersion: corpus.schemaVersion,
            modelDirectory: modelDirectory.standardizedFileURL.path,
            executionEnvironment: environment,
            promptStrategy: "archived-token-replay-vs-native-applyChatTemplate",
            generation: [
                "maxNewTokens": "512",
                "temperature": "0",
                "stopTokenIDs": "1,106",
            ],
            qualityReview: "unreviewed",
            productionRouting: false,
            rows: [],
            peakRSSBytes: peakRSS()
        )
        try write(report, to: outputURL)

        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        await container.update { context in
            context.configuration.extraEOSTokens.insert("<end_of_turn>")
            context.configuration.eosTokenIds.formUnion([1, 106])
        }
        report.status = "running"
        try write(report, to: outputURL)

        for row in corpus.results.prefix(limit) {
            guard !row.inputTokenIDs.isEmpty, row.inputTokenIDs.count <= 2_048 else {
                throw ProbeError.invalidCorpus
            }

            let prompt = try TranslateGemmaPrompt(targetText: row.input)
            let nativeTokens = try await container.perform { context in
                try context.tokenizer.applyChatTemplate(
                    messages: [prompt.modelMessage],
                    tools: nil,
                    additionalContext: nil
                )
            }
            guard !nativeTokens.isEmpty, nativeTokens.count <= 2_048 else {
                throw ProbeError.invalidPrompt(row.fixtureID)
            }

            let archived = try await generate(
                container: container,
                tokens: row.inputTokenIDs
            )
            let native = try await generate(
                container: container,
                tokens: nativeTokens
            )
            report.rows.append(
                RowReport(
                    fixtureID: row.fixtureID,
                    input: row.input,
                    intendedMeaning: row.intendedMeaning,
                    preservationNotes: row.preservationNotes,
                    contextMode: row.contextMode,
                    archivedPromptSHA256: sha256(row.actualInput.data(using: .utf8) ?? Data()),
                    nativePromptSHA256: sha256(
                        nativeTokens.map { String($0) }.joined(separator: ",").data(using: .utf8)
                            ?? Data()
                    ),
                    archivedPromptTokenCount: row.inputTokenIDs.count,
                    nativePromptTokenCount: nativeTokens.count,
                    archived: archived,
                    native: native
                )
            )
            report.peakRSSBytes = peakRSS()
            try write(report, to: outputURL)
        }

        report.status = "completed"
        report.peakRSSBytes = peakRSS()
        try write(report, to: outputURL)
    }

    private static func generate(
        container: ModelContainer,
        tokens: [Int]
    ) async throws -> Generation {
        let started = ProcessInfo.processInfo.systemUptime
        var output = ""
        var stopReason = "missing"
        var generatedTokenCount = 0
        for await event in try await container.generate(
            input: LMInput(tokens: MLXArray(tokens)),
            parameters: GenerateParameters(maxTokens: 512, temperature: 0)
        ) {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text):
                output += text
            case .info(let info):
                stopReason = String(describing: info.stopReason)
                generatedTokenCount = info.generationTokenCount
            case .toolCall:
                throw ProbeError.unexpectedToolCall
            @unknown default:
                throw ProbeError.missingCompletion("unknown-event")
            }
        }
        guard stopReason != "missing" else {
            throw ProbeError.missingCompletion("no-info-event")
        }
        return Generation(
            output: output,
            stopReason: stopReason,
            generatedTokenCount: generatedTokenCount,
            promptTokenCount: tokens.count,
            hitTokenLimit: generatedTokenCount >= 512 || stopReason == "length",
            durationSeconds: ProcessInfo.processInfo.systemUptime - started
        )
    }

    private static func verifyArtifacts(
        _ artifacts: [Corpus.Model.Artifact],
        in directory: URL
    ) throws {
        guard !artifacts.isEmpty else { throw ProbeError.invalidModelMetadata }
        for artifact in artifacts {
            guard !artifact.path.isEmpty,
                  !artifact.path.contains("/"),
                  artifact.path != ".",
                  artifact.path != "..",
                  artifact.bytes >= 0,
                  artifact.sha256.count == 64 else {
                throw ProbeError.invalidArtifactPath
            }
            let url = directory.appendingPathComponent(artifact.path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                throw ProbeError.artifactMissing(artifact.path)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
            guard size == artifact.bytes else {
                throw ProbeError.artifactIntegrity(artifact.path)
            }
            guard sha256(url) == artifact.sha256.lowercased() else {
                throw ProbeError.artifactIntegrity(artifact.path)
            }
        }
    }

    private static var environment: String {
        #if targetEnvironment(simulator)
        return "ios-simulator"
        #elseif os(iOS)
        return "ios-device"
        #else
        return "macos"
        #endif
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 4 * 1024 * 1024),
                  !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func peakRSS() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        return Int64(usage.ru_maxrss)
    }

    private static func write(_ report: Report, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(report).write(to: url, options: .atomic)
    }
}
