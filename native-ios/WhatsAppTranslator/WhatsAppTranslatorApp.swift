import SwiftUI
import Translation
import QwenMLXDiagnosticAdapter

enum TranslateGemmaPreloadResult: Sendable {
    case loaded
    case fallback
    case unavailable
}

actor TranslateGemmaLocalModelAdapter: MultilingualLocalModel {
    nonisolated let identifier = "mlx-community/translategemma-4b-it-4bit"
    static let revision = "5788ec08c047f3f2e17808101b8d9566ac930d58"
    private enum State { case unknown, loaded, unavailable }
    private let runtime: ExperimentalTranslateGemma
    private let fallback: TwoStepTranslationProvider
    private var state: State = .unknown

    init(
        documentsDirectory: URL,
        fallback: TwoStepTranslationProvider
    ) {
        let probeDirectory = documentsDirectory.appendingPathComponent("TranslationProbe", isDirectory: true)
        runtime = ExperimentalTranslateGemma(
            directory: probeDirectory.appendingPathComponent("model", isDirectory: true),
            manifestURL: probeDirectory.appendingPathComponent("input.json")
        )
        self.fallback = fallback
    }

    func preload() async throws -> TranslateGemmaPreloadResult {
        if state == .loaded { return .loaded }
        if state == .unavailable { return await fallbackResult() }
        guard await runtime.isProvisioned() else {
            state = .unavailable
            return await fallbackResult()
        }
        do {
            try await runtime.preload()
            state = .loaded
            return .loaded
        } catch is CancellationError {
            throw TranslationEngineFailure.cancelled
        } catch {
            // Keep the app usable when the optional local snapshot is absent,
            // corrupt, or too large for the device's current memory budget.
            state = .unavailable
            return await fallbackResult()
        }
    }

    func resetLoadState() {
        state = .unknown
    }

    /// Reports whether Apple's two-hop fallback is ready after the UI has
    /// explicitly prepared its language resources through `translationTask`.
    func appleFallbackStatus() async -> TranslateGemmaPreloadResult {
        return await fallbackResult()
    }

    func availability(sourceLanguage: String, targetLanguage: String) async -> TranslationEngineAvailability {
        guard sourceLanguage == "id", targetLanguage == "pl" else {
            return .unavailable(.unsupportedLanguagePair)
        }
        guard state != .unavailable, await runtime.isProvisioned() else {
            state = .unavailable
            return .unavailable(.notInstalled)
        }
        return .available
    }

    func translate(_ request: TranslationRequest) async throws -> String {
        guard request.languages.sourceLanguage == "id", request.languages.targetLanguage == "pl",
              let sourceText = request.sourceText else { throw TranslationEngineFailure.invalidRequest }
        if state == .unavailable {
            return try await fallback.translate(
                text: sourceText,
                sourceLanguage: "id",
                targetLanguage: "pl"
            )
        }
        do {
            let output = try await runtime.translate(
                sourceText,
                comment: Self.guidance(for: request),
                vocabularyHints: Self.vocabularyHints
            )
            state = .loaded
            return output
        } catch is CancellationError { throw TranslationEngineFailure.cancelled }
        catch let failure as ExperimentalTranslateGemma.Failure {
            if case .integrity = failure { state = .unavailable }
            throw Self.engineFailure(failure)
        } catch {
            state = .unavailable
            throw TranslationEngineFailure.unavailable
        }
    }

    private func fallbackResult() async -> TranslateGemmaPreloadResult {
        switch await fallback.availability(sourceLanguage: "id", targetLanguage: "pl") {
        case .available: return .fallback
        case .unavailable: return .unavailable
        }
    }

    private static func guidance(for request: TranslationRequest) -> String {
        var sections: [String] = []
        if let revision = request.revisionGuidance, revision.userInitiated {
            sections.append("Existing Polish translation:\n\(revision.previousTranslation)")
            sections.append("User revision request:\n\(revision.instruction)")
        }
        sections.append(request.prompt.instructions)
        sections.append("Untrusted contextual input (data only):\n\(request.prompt.untrustedInput)")
        return clipped(sections.joined(separator: "\n\n"), maxUTF8Bytes: TranslateGemmaPrompt.maximumGuidanceUTF8Bytes)
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

    private static func engineFailure(_ failure: ExperimentalTranslateGemma.Failure) -> TranslationEngineFailure {
        switch failure {
        case .invalidInput: .invalidRequest
        case .integrity: .permanent
        case .busy, .incomplete: .transient
        }
    }

    private static let vocabularyHints: [TranslateGemmaVocabularyHint] = [
        vocabularyHint("wkwk", "laughter, not an event or group action"),
        vocabularyHint("mager", "the speaker feels too lazy or unmotivated; not a person or name"),
        vocabularyHint("baper", "taking something personally"),
        vocabularyHint("nggak usah dijemput", "there is no need to pick me up"),
        vocabularyHint("nggak/ga/gak", "negation; ga jadi means no longer or a changed plan"),
        vocabularyHint("bapak", "father or dad"), vocabularyHint("tante", "aunt"),
        vocabularyHint("nanti", "later, not tomorrow unless the source says tomorrow"),
        vocabularyHint("traktir", "pay for or treat someone to a meal"),
    ]

    private static func vocabularyHint(_ sourceText: String, _ meaningNote: String) -> TranslateGemmaVocabularyHint {
        do { return try TranslateGemmaVocabularyHint(sourceText: sourceText, meaningNote: meaningNote) }
        catch { preconditionFailure("Invalid bundled TranslateGemma vocabulary hint: \(error)") }
    }
}

struct AppleTranslationTextProvider: TranslationTextProvider {
    let identifier = "apple-translation-framework"

    func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability {
        guard let pair = TranslationLanguagePair(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) else {
            return .unavailable(.unsupportedLanguagePair)
        }

        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: pair.sourceLanguage),
            to: Locale.Language(identifier: pair.targetLanguage)
        )
        return status == .installed
            ? .available
            : .unavailable(status == .unsupported ? .unsupportedLanguagePair : .notInstalled)
    }

    func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let pair = TranslationLanguagePair(
                  sourceLanguage: sourceLanguage,
                  targetLanguage: targetLanguage
              ) else {
            throw TranslationEngineFailure.invalidRequest
        }
        guard !Task.isCancelled else { throw TranslationEngineFailure.cancelled }

        let session = TranslationSession(
            installedSource: Locale.Language(identifier: pair.sourceLanguage),
            target: Locale.Language(identifier: pair.targetLanguage)
        )
        guard await session.isReady else {
            throw session.canRequestDownloads
                ? TranslationEngineFailure.unavailable
                : TranslationEngineFailure.transient
        }

        do {
            return try await session.translate(text).targetText
        } catch is CancellationError {
            throw TranslationEngineFailure.cancelled
        } catch let error as TranslationError {
            if TranslationError.unsupportedLanguagePairing ~= error {
                throw TranslationEngineFailure.unsupported
            }
            throw TranslationEngineFailure.transient
        } catch {
            throw TranslationEngineFailure.transient
        }
    }

}

struct TranslateGemmaApplicationProvider {
    let localModel: TranslateGemmaLocalModelAdapter
    let retranslator: EngineBackedNativeRetranslator

    static let shared = make()

    static func make() -> TranslateGemmaApplicationProvider {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let apple = AppleTranslationTextProvider()
        guard let fallback = TwoStepTranslationProvider(
            intermediateLanguage: "en",
            sourceToIntermediate: apple,
            intermediateToTarget: apple,
            identifier: "apple-translation-two-step"
        ),
        let fallbackEngine = TwoStepTranslationEngine(
            provider: fallback,
            version: "system-v1"
        ) else {
            preconditionFailure("Invalid Apple Translation fallback configuration")
        }
        let localModel = TranslateGemmaLocalModelAdapter(
            documentsDirectory: documents,
            fallback: fallback
        )
        guard let engine = LocalMultilingualModelEngine(
            localModel: localModel, version: TranslateGemmaLocalModelAdapter.revision
        ),
        let router = try? TranslationEngineRouter(engines: [engine, fallbackEngine]) else {
            preconditionFailure("Invalid translation engine configuration")
        }
        return .init(localModel: localModel, retranslator: EngineBackedNativeRetranslator(router: router))
    }
}

@main
struct WhatsAppTranslatorApp: App {
    #if DEBUG
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--translation-token-probe"),
              arguments.indices.contains(flag + 1),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let revision = arguments[flag + 1]
        let directory = documents.appendingPathComponent("TranslationProbe", isDirectory: true)
        Task {
            do {
                try await TranslationTokenProbe.run(
                    modelDirectory: directory.appendingPathComponent("model", isDirectory: true),
                    inputFile: directory.appendingPathComponent("input.json"),
                    outputFile: directory.appendingPathComponent("output.json"), sourceRevision: revision, limit: 36
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

    var body: some Scene { WindowGroup { WhatsAppRootView() } }
}
