import SwiftUI
import QwenMLXDiagnosticAdapter

actor TranslateGemmaChatRetranslator: NativeRetranslator {
    nonisolated let isValidated = false
    private static let sharedApplicationProvider: TranslateGemmaChatRetranslator = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return TranslateGemmaChatRetranslator(documentsDirectory: documents)
    }()
    private let engine: ExperimentalTranslateGemma
    private var inferenceActive = false
    private var inferenceWaiters: [CheckedContinuation<Void, Never>] = []

    init(documentsDirectory: URL) {
        let probeDirectory = documentsDirectory.appendingPathComponent("TranslationProbe", isDirectory: true)
        engine = ExperimentalTranslateGemma(
            directory: probeDirectory.appendingPathComponent("model", isDirectory: true),
            manifestURL: probeDirectory.appendingPathComponent("input.json")
        )
    }

    static func applicationProvider() -> TranslateGemmaChatRetranslator {
        sharedApplicationProvider
    }

    func preload() async throws {
        await acquireInferenceSlot()
        defer { releaseInferenceSlot() }
        try await engine.preload()
    }

    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart] {
        await acquireInferenceSlot()
        defer { releaseInferenceSlot() }
        let output = try await engine.translate(
            request.original,
            comment: request.comment,
            vocabularyHints: Self.vocabularyHints
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw ExperimentalTranslateGemma.Failure.incomplete }
        return [.init(id: "translategemma-\(request.revision)", source: nil, translation: output)]
    }

    private func acquireInferenceSlot() async {
        guard inferenceActive else {
            inferenceActive = true
            return
        }
        await withCheckedContinuation { continuation in
            inferenceWaiters.append(continuation)
        }
    }

    private func releaseInferenceSlot() {
        guard !inferenceWaiters.isEmpty else {
            inferenceActive = false
            return
        }
        inferenceWaiters.removeFirst().resume()
    }

    private static let vocabularyHints: [TranslateGemmaVocabularyHint] = [
        try! .init(sourceText: "wkwk", meaningNote: "laughter, not an event or group action"),
        try! .init(sourceText: "mager", meaningNote: "the speaker feels too lazy or unmotivated; not a person or name"),
        try! .init(sourceText: "baper", meaningNote: "taking something personally"),
        try! .init(sourceText: "nggak usah dijemput", meaningNote: "there is no need to pick me up"),
        try! .init(sourceText: "nggak/ga/gak", meaningNote: "negation; ga jadi means no longer or a changed plan"),
        try! .init(sourceText: "bapak", meaningNote: "father or dad"),
        try! .init(sourceText: "tante", meaningNote: "aunt"),
        try! .init(sourceText: "nanti", meaningNote: "later, not tomorrow unless the source says tomorrow"),
        try! .init(sourceText: "traktir", meaningNote: "pay for or treat someone to a meal"),
    ]
}

@main
struct WhatsAppTranslatorApp: App {
    #if DEBUG
    init() {
        // Explicit local diagnostic launch only. Never routes chat messages.
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--translation-token-probe"),
              arguments.indices.contains(flag + 1),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let revision = arguments[flag + 1]
        let directory = documents.appendingPathComponent("TranslationProbe", isDirectory: true)
        Task {
            do {
                try await TranslationTokenProbe.run(
                    modelDirectory: directory.appendingPathComponent("model", isDirectory: true),
                    inputFile: directory.appendingPathComponent("input.json"),
                    outputFile: directory.appendingPathComponent("output.json"),
                    sourceRevision: revision, limit: 36
                )
            } catch {
                let failure = ["status": "failed", "failure": String(describing: error)]
                if let data = try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys]) {
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? data.write(to: directory.appendingPathComponent("failure.json"), options: .atomic)
                }
            }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            WhatsAppRootView()
        }
    }
}
