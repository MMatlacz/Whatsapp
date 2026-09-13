import SwiftUI
import QwenMLXDiagnosticAdapter

actor TranslateGemmaChatRetranslator: NativeRetranslator {
    nonisolated let isValidated = false
    private static let manualRevisionPrefix = "Revise the Polish output according to the request below. If it asks about a term or comparison, include a brief Polish explanation after the translation."
    private static let sharedApplicationProvider: TranslateGemmaChatRetranslator = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return TranslateGemmaChatRetranslator(documentsDirectory: documents)
    }()
    private let engine: ExperimentalTranslateGemma
    private var inferenceActive = false

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
        try await acquireInferenceSlot(waitIfBusy: false)
        defer { inferenceActive = false }
        try await engine.preload()
    }

    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart] {
        // A fast scroll can create many translation cards at once. Do not
        // retain an unbounded queue of inference continuations: one request
        // runs and the remaining cards stay available for an explicit retry.
        do {
            try await acquireInferenceSlot(waitIfBusy: request.userInitiated)
            defer { inferenceActive = false }
            let guidance = request.userInitiated
                ? Self.manualGuidance(for: request)
                : request.comment
            guard guidance.utf8.count <= TranslateGemmaPrompt.maximumGuidanceUTF8Bytes else {
                throw NativeRetranslationFailure.invalidInput
            }
            let output = try await engine.translate(
                request.original,
                comment: guidance,
                vocabularyHints: Self.vocabularyHints
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { throw NativeRetranslationFailure.incomplete }
            return [.init(id: "translategemma-\(request.revision)", source: nil, translation: output)]
        } catch is CancellationError {
            throw NativeRetranslationFailure.cancelled
        } catch let failure as NativeRetranslationFailure {
            throw failure
        } catch let failure as ExperimentalTranslateGemma.Failure {
            switch failure {
            case .busy: throw NativeRetranslationFailure.busy
            case .invalidInput: throw NativeRetranslationFailure.invalidInput
            case .integrity: throw NativeRetranslationFailure.integrity
            case .incomplete: throw NativeRetranslationFailure.incomplete
            }
        } catch {
            throw NativeRetranslationFailure.unavailable
        }
    }

    private static func manualGuidance(for request: NativeRetranslationRequest) -> String {
        let previous = clipped(request.previousTranslation, maxUTF8Bytes: 800)
        let instruction = clipped(request.comment, maxUTF8Bytes: 800)
        return """
        \(manualRevisionPrefix)
        Existing Polish translation:
        \(previous.isEmpty ? "(none yet)" : previous)
        User revision request:
        \(instruction)
        """
    }

    private static func clipped(_ value: String, maxUTF8Bytes: Int) -> String {
        var used = 0
        return String(value.prefix { character in
            let count = String(character).utf8.count
            guard used + count <= maxUTF8Bytes else { return false }
            used += count
            return true
        })
    }

    private func acquireInferenceSlot(waitIfBusy: Bool) async throws {
        while inferenceActive {
            guard waitIfBusy else { throw ExperimentalTranslateGemma.Failure.busy }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        inferenceActive = true
    }

    private static let vocabularyHints: [TranslateGemmaVocabularyHint] = [
        vocabularyHint("wkwk", "laughter, not an event or group action"),
        vocabularyHint("mager", "the speaker feels too lazy or unmotivated; not a person or name"),
        vocabularyHint("baper", "taking something personally"),
        vocabularyHint("nggak usah dijemput", "there is no need to pick me up"),
        vocabularyHint("nggak/ga/gak", "negation; ga jadi means no longer or a changed plan"),
        vocabularyHint("bapak", "father or dad"),
        vocabularyHint("tante", "aunt"),
        vocabularyHint("nanti", "later, not tomorrow unless the source says tomorrow"),
        vocabularyHint("traktir", "pay for or treat someone to a meal"),
    ]

    private static func vocabularyHint(_ sourceText: String, _ meaningNote: String) -> TranslateGemmaVocabularyHint {
        do {
            return try TranslateGemmaVocabularyHint(sourceText: sourceText, meaningNote: meaningNote)
        } catch {
            preconditionFailure("Invalid bundled TranslateGemma vocabulary hint: \(error)")
        }
    }
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
