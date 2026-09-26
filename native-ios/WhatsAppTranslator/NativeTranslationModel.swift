import Foundation
import Observation
#if SWIFT_PACKAGE
import PersistenceCore
import TranslationCore
import WhatsAppDomainCore
#endif

struct NativeTranslationKey: Hashable, Codable, Sendable {
    let chatID: String
    let messageID: String
    let sourceLanguage: String
    let targetLanguage: String
}

struct NativeTranslationProvenance: Equatable, Codable, Sendable {
    let contextHash: String
    let promptVersion: String
    let modelIdentifier: String
    let contextMessageCount: Int
    let summaryVersion: Int?
}

struct NativeTranslationPart: Equatable, Codable, Identifiable, Sendable {
    let id: String
    let source: String?
    var translation: String
    let provenance: NativeTranslationProvenance?

    init(
        id: String,
        source: String?,
        translation: String,
        provenance: NativeTranslationProvenance? = nil
    ) {
        self.id = id
        self.source = source
        self.translation = translation
        self.provenance = provenance
    }
}

struct NativeTranslationRecord: Equatable, Codable, Sendable {
    let original: String
    var parts: [NativeTranslationPart]
    var revision: Int
    var manuallyEdited: Bool
    var comment: String
    var isSample: Bool
    var provenance: NativeTranslationProvenance?

    init(
        original: String,
        parts: [NativeTranslationPart],
        revision: Int = 1,
        manuallyEdited: Bool = false,
        comment: String = "",
        isSample: Bool = false,
        provenance: NativeTranslationProvenance? = nil
    ) {
        self.original = original
        self.parts = parts
        self.revision = revision
        self.manuallyEdited = manuallyEdited
        self.comment = comment
        self.isSample = isSample
        self.provenance = provenance
    }

    var translatedText: String { parts.map(\.translation).joined() }
}

struct NativeRetranslationRequest: Equatable, Sendable {
    let key: NativeTranslationKey
    let original: String
    let previousTranslation: String
    let comment: String
    let revision: Int
    let userInitiated: Bool
    let promptContract: TranslationPromptContract?

    init(
        key: NativeTranslationKey,
        original: String,
        previousTranslation: String,
        comment: String,
        revision: Int,
        userInitiated: Bool,
        promptContract: TranslationPromptContract? = nil
    ) {
        self.key = key
        self.original = original
        self.previousTranslation = previousTranslation
        self.comment = comment
        self.revision = revision
        self.userInitiated = userInitiated
        self.promptContract = promptContract
    }
}

enum NativeRetranslationFailure: Error, Equatable, Sendable {
    case busy
    case invalidInput
    case unavailable
    case integrity
    case incomplete
    case cancelled
}

enum NativeTranslationExecutionKind: Equatable, Sendable {
    case manual
    case automatic
}

enum NativeTranslationExecutionResult: Equatable, Sendable {
    case completed
    case failed
    case cancelled
}

enum NativeTranslationSchedulingOutcome: Equatable, Sendable {
    case completed
    case failed
    case cancelled
    case superseded
    case deduplicated
    case queueFull
}

enum NativeTranslationExecutionState: Equatable, Sendable {
    case queuedManual
    case queuedAutomatic
    case runningManual
    case runningAutomatic
    case completed
    case failed
    case cancelled
    case superseded
    case queueFull
}

actor TranslationInferenceScheduler {
    static let defaultMaximumQueuedAutomaticJobs = 12

    private typealias Operation = @Sendable () async -> NativeTranslationExecutionResult

    private struct Job {
        let id: UUID
        let key: NativeTranslationKey
        let kind: NativeTranslationExecutionKind
        let operation: Operation
        let continuation: CheckedContinuation<NativeTranslationSchedulingOutcome, Never>
    }

    private struct ActiveJob {
        let job: Job
        let task: Task<Void, Never>
    }

    private let maximumQueuedAutomaticJobs: Int
    private var active: ActiveJob?
    private var manualQueue: [Job] = []
    private var automaticQueue: [Job] = []
    private var cancelledActiveIDs: Set<UUID> = []
    private var states: [NativeTranslationKey: NativeTranslationExecutionState] = [:]

    init(
        maximumQueuedAutomaticJobs: Int = TranslationInferenceScheduler.defaultMaximumQueuedAutomaticJobs
    ) {
        precondition(maximumQueuedAutomaticJobs > 0)
        self.maximumQueuedAutomaticJobs = maximumQueuedAutomaticJobs
    }

    func submit(
        key: NativeTranslationKey,
        kind: NativeTranslationExecutionKind,
        operation: @escaping @Sendable () async -> NativeTranslationExecutionResult
    ) async -> NativeTranslationSchedulingOutcome {
        if kind == .automatic {
            if active?.job.kind == .automatic, active?.job.key == key {
                return .deduplicated
            }
            if automaticQueue.contains(where: { $0.key == key }) {
                return .deduplicated
            }
            if automaticQueue.count >= maximumQueuedAutomaticJobs {
                states[key] = .queueFull
                return .queueFull
            }
        }

        return await withCheckedContinuation { continuation in
            if kind == .manual,
               let existing = manualQueue.firstIndex(where: { $0.key == key }) {
                let superseded = manualQueue.remove(at: existing)
                superseded.continuation.resume(returning: .superseded)
            }

            let job = Job(
                id: UUID(),
                key: key,
                kind: kind,
                operation: operation,
                continuation: continuation
            )
            if active == nil {
                start(job)
            } else {
                switch kind {
                case .manual:
                    manualQueue.append(job)
                    states[key] = .queuedManual
                case .automatic:
                    automaticQueue.append(job)
                    states[key] = .queuedAutomatic
                }
            }
        }
    }

    @discardableResult
    func cancelAutomatic(for key: NativeTranslationKey) -> Bool {
        var cancelled = false

        if let index = automaticQueue.firstIndex(where: { $0.key == key }) {
            let job = automaticQueue.remove(at: index)
            states[key] = .cancelled
            job.continuation.resume(returning: .cancelled)
            cancelled = true
        }

        if let active, active.job.kind == .automatic, active.job.key == key {
            cancelledActiveIDs.insert(active.job.id)
            states[key] = .cancelled
            active.task.cancel()
            cancelled = true
        }

        return cancelled
    }

    func state(for key: NativeTranslationKey) -> NativeTranslationExecutionState? {
        states[key]
    }

    func snapshot() -> [NativeTranslationKey: NativeTranslationExecutionState] {
        states
    }

    func queuedAutomaticCount() -> Int {
        automaticQueue.count
    }

    private func start(_ job: Job) {
        states[job.key] = job.kind == .manual ? .runningManual : .runningAutomatic
        let id = job.id
        let operation = job.operation
        let task = Task { [weak self] in
            let result = await operation()
            await self?.finish(id: id, result: result)
        }
        active = ActiveJob(job: job, task: task)
    }

    private func finish(id: UUID, result: NativeTranslationExecutionResult) {
        guard let active, active.job.id == id else { return }
        let job = active.job
        let wasCancelled = cancelledActiveIDs.remove(id) != nil
        self.active = nil

        let outcome: NativeTranslationSchedulingOutcome
        if wasCancelled || result == .cancelled {
            states[job.key] = .cancelled
            outcome = .cancelled
        } else {
            switch result {
            case .completed:
                states[job.key] = .completed
                outcome = .completed
            case .failed:
                states[job.key] = .failed
                outcome = .failed
            case .cancelled:
                states[job.key] = .cancelled
                outcome = .cancelled
            }
        }
        job.continuation.resume(returning: outcome)
        startNext()
    }

    private func startNext() {
        if !manualQueue.isEmpty {
            start(manualQueue.removeFirst())
        } else if !automaticQueue.isEmpty {
            start(automaticQueue.removeFirst())
        }
    }
}

protocol NativeRetranslator: Sendable {
    /// Translation quality has to be reviewed against the shared benchmark
    /// before this capability can affect a chat. Implementations are
    /// unvalidated by default so adding a provider cannot silently enable it.
    var isValidated: Bool { get }

    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart]
}

extension NativeRetranslator {
    var isValidated: Bool { false }
}

@available(iOS 17, macOS 14, *)
@MainActor @Observable
final class NativeTranslationModel {
    private(set) var records: [NativeTranslationKey: NativeTranslationRecord] = [:]
    private(set) var knownWords: Set<String> = []
    private(set) var running: Set<NativeTranslationKey> = []
    private(set) var executionStates: [NativeTranslationKey: NativeTranslationExecutionState] = [:]
    private(set) var notices: [NativeTranslationKey: String] = [:]
    private(set) var storageError: String?
    var showKnownWords = false
    var experimentalTranslationEnabled = false
    var ownerApprovedExperimentalProvider = false
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let retranslator: (any NativeRetranslator)?
    @ObservationIgnored private let contextStore: SQLiteContextStore?
    @ObservationIgnored private let inferenceScheduler = TranslationInferenceScheduler()

    init(fileURL: URL? = nil, retranslator: (any NativeRetranslator)? = nil,
         contextStore: SQLiteContextStore? = nil) {
        self.fileURL = fileURL
        self.retranslator = retranslator
        self.contextStore = contextStore

        var loadedDatabase = false
        if let contextStore {
            do {
                let saved = try contextStore.latestTranslations()
                records = Self.records(from: saved)
                for intent in try contextStore.allTranslationIntents() {
                    let key = NativeTranslationKey(
                        chatID: intent.chatID.rawValue,
                        messageID: intent.messageID.rawValue,
                        sourceLanguage: intent.sourceLanguage,
                        targetLanguage: intent.targetLanguage
                    )
                    if var existing = records[key], existing.original == intent.sourceText {
                        existing.comment = intent.correctionComment
                        records[key] = existing
                    } else if records[key] == nil {
                        records[key] = NativeTranslationRecord(
                            original: intent.sourceText,
                            parts: [],
                            revision: 0,
                            comment: intent.correctionComment
                        )
                    }
                }
                knownWords = try contextStore.allKnownWords().reduce(into: Set<String>()) { result, word in
                    result.insert(Self.wordKey(word.normalizedText, language: word.language))
                }
                loadedDatabase = true
            } catch {
                storageError = "Saved translation data could not be read. The database has not been overwritten."
            }
        }

        // Keep the old file as a recoverable migration/fallback path. A
        // malformed legacy file must never replace valid database state. When
        // SQLite is available, import every legacy value in one transaction;
        // importing only the last edited key would lose the untouched keys on
        // the next restart.
        guard storageError == nil,
              let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let saved = try Self.loadLegacySnapshot(from: fileURL)
            guard loadedDatabase, let contextStore else {
                // A model constructed without SQLite still supports the
                // recoverable legacy store used by older callers and tests.
                if records.isEmpty { records = saved.records }
                if knownWords.isEmpty { knownWords = saved.knownWords }
                return
            }
            let databaseRecords = records
            let databaseWords = knownWords
            var mergedRecords = records
            var recordsToImport: [StoredTranslation] = []

            for (key, legacyRecord) in saved.records {
                let shouldUseLegacy = databaseRecords[key].map {
                    legacyRecord.revision > $0.revision
                } ?? true
                if shouldUseLegacy {
                    mergedRecords[key] = legacyRecord
                    if !legacyRecord.isSample {
                        recordsToImport.append(try storedTranslation(
                            record: legacyRecord,
                            key: key,
                            revisionKind: inferredRevisionKind(for: legacyRecord),
                            knownWordsVersion: try contextStore.knownWordsVersion()
                        ))
                    }
                }
            }

            let wordsToImport = saved.knownWords.subtracting(databaseWords).compactMap {
                Self.storedKnownWord(from: $0)
            }
            // A malformed key is a migration failure, rather than a reason to
            // silently discard a user's vocabulary. The database transaction
            // below still protects against partial writes for SQL failures.
            guard wordsToImport.count == saved.knownWords.subtracting(databaseWords).count else {
                throw SQLiteContextPersistenceError.invalidStoredValue("known_words.key")
            }

            records = mergedRecords
            knownWords.formUnion(saved.knownWords.subtracting(databaseWords))
            if !recordsToImport.isEmpty || !wordsToImport.isEmpty {
                try contextStore.importInitialState(
                    translations: recordsToImport,
                    knownWords: wordsToImport
                )
            }
        } catch {
            storageError = "Saved translation edits could not be migrated. The legacy copy has been kept."
        }
    }

    static func applicationStore(retranslator: (any NativeRetranslator)? = nil) -> NativeTranslationModel {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let legacyURL = directory?
            .appendingPathComponent("NativeTranslationEdits", isDirectory: true)
            .appendingPathComponent("edits-v1.json")
        let databaseURL = directory?
            .appendingPathComponent("NativeChats", isDirectory: true)
            .appendingPathComponent("chats.sqlite")
        guard let databaseURL else {
            let model = NativeTranslationModel(fileURL: legacyURL, retranslator: retranslator)
            model.storageError = "SQLite translation storage is unavailable (application-support-directory-unavailable). Translation changes are disabled."
            return model
        }

        var failedAt = "create-database-directory"
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            failedAt = "sqlite-open-or-migration"
            let contextStore = try SQLiteContextStore(path: databaseURL.path)
            return NativeTranslationModel(fileURL: legacyURL, retranslator: retranslator,
                                          contextStore: contextStore)
        } catch {
            // Keep the legacy file available for recovery, but expose the
            // database failure instead of silently pretending SQLite opened.
            let model = NativeTranslationModel(fileURL: legacyURL, retranslator: retranslator)
            model.storageError = "SQLite translation storage is unavailable (\(failedAt), \(NativeStorageDiagnostic.code(for: error))). Translation changes are disabled."
            return model
        }
    }

    func record(for key: NativeTranslationKey, original: String) -> NativeTranslationRecord? {
        guard let record = records[key], record.original == original else { return nil }
        return record
    }

    func seedSample(key: NativeTranslationKey, original: String, parts: [NativeTranslationPart]) {
        guard records[key] == nil else { return }
        records[key] = NativeTranslationRecord(original: original, parts: parts, isSample: true)
    }

    func isKnown(_ source: String, language: String) -> Bool {
        knownWords.contains(Self.wordKey(source, language: language))
    }

    func toggleKnown(_ source: String, language: String) {
        let word = Self.wordKey(source, language: language)
        var updated = knownWords
        if !updated.insert(word).inserted { updated.remove(word) }
        commit(records: records, words: updated)
    }

    func displayText(for record: NativeTranslationRecord, language: String) -> String {
        record.parts.map { part in
            if showKnownWords, let source = part.source, isKnown(source, language: language) { return source }
            return part.translation
        }.joined()
    }

    @discardableResult
    func saveCorrection(key: NativeTranslationKey, original: String,
                        parts: [NativeTranslationPart], expectedRevision: Int) -> Bool {
        let current = record(for: key, original: original)
        guard (current?.revision ?? 0) == expectedRevision else {
            notices[key] = "Translation changed while editing. Reopen the editor to avoid overwriting it."
            return false
        }
        guard !parts.map(\.translation).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notices[key] = "The translation cannot be empty."
            return false
        }
        guard Self.validParts(parts, original: original) else {
            notices[key] = "The translation mapping is invalid. The original message was not changed."
            return false
        }
        var updated = records
        updated[key] = NativeTranslationRecord(
            original: original, parts: parts, revision: expectedRevision + 1,
            manuallyEdited: true, comment: current?.comment ?? "", isSample: current?.isSample ?? false,
            provenance: current?.provenance
        )
        guard commit(records: updated, words: knownWords, changedKey: key, revisionKind: .manualEdit) else {
            return false
        }
        notices[key] = "Manual correction saved locally. Original message unchanged."
        return true
    }

    func retranslate(key: NativeTranslationKey, original: String, comment: String) async {
        await performRetranslation(key: key, original: original, comment: comment, userInitiated: true)
    }

    func inferenceState(for key: NativeTranslationKey) async -> NativeTranslationExecutionState? {
        executionStates[key]
    }

    func inferenceStates() async -> [NativeTranslationKey: NativeTranslationExecutionState] {
        executionStates
    }

    func cancelAutomaticTranslation(for key: NativeTranslationKey) async {
        _ = await inferenceScheduler.cancelAutomatic(for: key)
        if let state = await inferenceScheduler.state(for: key) {
            executionStates[key] = state
        }
    }

    private func performRetranslation(
        key: NativeTranslationKey,
        original: String,
        comment: String,
        userInitiated: Bool
    ) async {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if userInitiated {
            var current = record(for: key, original: original)
                ?? NativeTranslationRecord(original: original, parts: [], revision: 0)
            current.comment = trimmed
            guard persistCorrectionIntent(key: key, record: current) else { return }
        }

        guard let retranslator, retranslator.isValidated || ownerApprovedExperimentalProvider else {
            notices[key] = userInitiated
                ? "Comment saved. Retranslation is blocked until a validated translation engine is enabled. No model was run."
                : "No validated local translation model is installed and configured. No model was run."
            return
        }

        let kind: NativeTranslationExecutionKind = userInitiated ? .manual : .automatic
        executionStates[key] = userInitiated ? .queuedManual : .queuedAutomatic
        let outcome = await inferenceScheduler.submit(key: key, kind: kind) { [weak self] in
            guard let self else { return .cancelled }
            return await self.executeRetranslation(
                key: key,
                original: original,
                comment: trimmed,
                userInitiated: userInitiated,
                retranslator: retranslator
            )
        }

        if let state = await inferenceScheduler.state(for: key) {
            executionStates[key] = state
        }

        switch outcome {
        case .queueFull:
            if !userInitiated {
                notices[key] = "Automatic translation queue is full. This message was not changed."
            }
        case .cancelled:
            if userInitiated {
                notices[key] = "Retranslation was cancelled. Your previous translation and comment are kept."
            }
        case .superseded, .deduplicated, .completed, .failed:
            break
        }
    }

    private func executeRetranslation(
        key: NativeTranslationKey,
        original: String,
        comment: String,
        userInitiated: Bool,
        retranslator: any NativeRetranslator
    ) async -> NativeTranslationExecutionResult {
        guard !Task.isCancelled else { return .cancelled }

        var current = record(for: key, original: original)
            ?? NativeTranslationRecord(original: original, parts: [], revision: 0)
        let baselineRevision = current.revision
        let baselineComment = current.comment
        let requestRevision = max(1, baselineRevision + 1)

        executionStates[key] = userInitiated ? .runningManual : .runningAutomatic
        running.insert(key)
        defer { running.remove(key) }

        do {
            try Task.checkCancellation()
            let promptContract = try await productionPromptContract(for: key)
            try Task.checkCancellation()

            let parts = try await retranslator.retranslate(.init(
                key: key,
                original: original,
                previousTranslation: current.translatedText,
                comment: comment,
                revision: requestRevision,
                userInitiated: userInitiated,
                promptContract: promptContract
            ))
            try Task.checkCancellation()

            let latest = record(for: key, original: original)
            guard (latest?.revision ?? 0) == baselineRevision,
                  (latest?.comment ?? "") == baselineComment else {
                return .cancelled
            }
            guard Self.validParts(parts, original: original) else {
                notices[key] = "The translation result was invalid. Your previous translation is kept."
                return .failed
            }

            let translationChanged = current.translatedText != parts.map(\.translation).joined()
            let hadTranslation = !current.parts.isEmpty
            current.parts = parts
            current.manuallyEdited = false
            current.revision = requestRevision
            current.provenance = parts.compactMap(\.provenance).first

            try Task.checkCancellation()
            var updated = records
            updated[key] = current
            let revisionKind: TranslationRevisionKind = hadTranslation ? .retranslation : .model
            guard commit(
                records: updated,
                words: knownWords,
                changedKey: key,
                revisionKind: revisionKind
            ) else {
                return .failed
            }

            if userInitiated {
                notices[key] = translationChanged
                    ? "Retranslation updated using your comment."
                    : "The model returned the same translation. Your comment was saved; try a more specific instruction."
            } else {
                notices[key] = "Translation updated."
            }
            return .completed
        } catch is CancellationError {
            if userInitiated {
                notices[key] = "Retranslation was cancelled. Your previous translation and comment are kept."
            }
            return .cancelled
        } catch let failure as NativeRetranslationFailure {
            notices[key] = failureNotice(failure, userInitiated: userInitiated)
            return failure == .cancelled ? .cancelled : .failed
        } catch {
            notices[key] = userInitiated
                ? "Retranslation failed. Your previous translation and comment are kept."
                : "Translation failed. Tap Translate now to retry."
            return .failed
        }
    }

    private func persistCorrectionIntent(key: NativeTranslationKey, record: NativeTranslationRecord) -> Bool {
        var updated = records
        updated[key] = record
        guard storageError == nil else { return false }
        if let contextStore, !record.isSample {
            do {
                guard let chatID = WhatsAppChatID(key.chatID),
                      let messageID = WhatsAppMessageID(key.messageID),
                      let intent = StoredTranslationIntent(
                        chatID: chatID,
                        messageID: messageID,
                        sourceLanguage: key.sourceLanguage,
                        targetLanguage: key.targetLanguage,
                        sourceText: record.original,
                        correctionComment: record.comment,
                        updatedAt: Self.currentTimestamp()
                      ) else {
                    throw SQLiteContextPersistenceError.invalidStoredValue("translation_intent")
                }
                try contextStore.upsert(translationIntent: intent)
                records = updated
                return true
            } catch {
                storageError = "Could not save the retranslation comment. Your previous saved data is kept."
                return false
            }
        }
        return commit(records: updated, words: knownWords)
    }

    private func productionPromptContract(for key: NativeTranslationKey) async throws -> TranslationPromptContract? {
        guard let contextStore else { return nil }
        guard let chatID = WhatsAppChatID(key.chatID),
              let messageID = WhatsAppMessageID(key.messageID) else {
            throw NativeRetranslationFailure.invalidInput
        }

        return try await PersistenceBackedTranslationPromptAssembler(
            source: SQLiteTranslationContextSource(store: contextStore)
        ).assemble(
            chatID: chatID,
            messageID: messageID,
            sourceLanguage: key.sourceLanguage,
            targetLanguage: key.targetLanguage
        )
    }

    private func failureNotice(_ failure: NativeRetranslationFailure, userInitiated: Bool) -> String {
        switch failure {
        case .busy:
            return userInitiated
                ? "Retranslation is waiting on another local inference. Your comment is saved; retry if it does not start."
                : "Translation was deferred while the local model was busy. Tap Translate now to retry."
        case .invalidInput:
            return userInitiated
                ? "The retranslation request is too large or unsupported. Your previous translation and comment are kept."
                : "This message could not be processed by the local translation model."
        case .unavailable:
            return "The local translation model is unavailable. Your saved content is unchanged."
        case .integrity:
            return "The local translation model failed integrity verification. No translation was changed."
        case .incomplete:
            return userInitiated
                ? "The model did not return a complete revision. Your previous translation and comment are kept."
                : "The model did not return a complete translation. Tap Translate now to retry."
        case .cancelled:
            return userInitiated
                ? "Retranslation was cancelled. Your previous translation and comment are kept."
                : "Translation was cancelled before completion."
        }
    }

    func translate(key: NativeTranslationKey, original: String) async {
        guard experimentalTranslationEnabled else {
            notices[key] = "Automatic translation is disabled until a validated engine passes quality and resource review."
            return
        }
        guard let retranslator, retranslator.isValidated || ownerApprovedExperimentalProvider else {
            notices[key] = "No validated local translation model is installed and configured. No model was run."
            return
        }
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record(for: key, original: original)?.parts.isEmpty != false else { return }
        await performRetranslation(
            key: key,
            original: original,
            comment: "Translate faithfully. Preserve meaning, tone and quoted references.",
            userInitiated: false
        )
    }

    private static func wordKey(_ word: String, language: String) -> String {
        language.lowercased() + "\u{0}" + word.precomposedStringWithCanonicalMapping.lowercased()
    }

    @discardableResult
    private func commit(records: [NativeTranslationKey: NativeTranslationRecord], words: Set<String>,
                        changedKey: NativeTranslationKey? = nil,
                        revisionKind: TranslationRevisionKind? = nil) -> Bool {
        guard storageError == nil else { return false }
        if let contextStore {
            do {
                if let changedKey, let changed = records[changedKey],
                   self.records[changedKey] != changed, !changed.isSample {
                    try persist(record: changed, key: changedKey,
                                revisionKind: revisionKind ?? inferredRevisionKind(for: changed))
                } else {
                    for (key, record) in records where self.records[key] != record && !record.isSample {
                        try persist(record: record, key: key,
                                    revisionKind: revisionKind ?? inferredRevisionKind(for: record))
                    }
                }

                for rawWord in words.subtracting(knownWords) {
                    guard let value = Self.parseWordKey(rawWord) else {
                        throw SQLiteContextPersistenceError.invalidStoredValue("known_words.key")
                    }
                    let now = Self.currentTimestamp()
                    guard let entry = StoredKnownWord(
                        language: value.language,
                        normalizedText: value.normalizedText,
                        displayText: value.normalizedText,
                        createdAt: now,
                        updatedAt: now
                    ) else {
                        throw SQLiteContextPersistenceError.invalidStoredValue("known_words")
                    }
                    try contextStore.upsert(knownWord: entry)
                }
                for rawWord in knownWords.subtracting(words) {
                    guard let value = Self.parseWordKey(rawWord) else {
                        throw SQLiteContextPersistenceError.invalidStoredValue("known_words.key")
                    }
                    try contextStore.deleteKnownWord(language: value.language,
                                                     normalizedText: value.normalizedText)
                }
            } catch {
                storageError = "Could not save translation changes. Your previous saved data is kept."
                return false
            }
        } else if let fileURL {
            do {
                var directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                let data = try JSONEncoder().encode(Snapshot(version: 1, records: records, knownWords: words))
                #if os(iOS)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                #else
                try data.write(to: fileURL, options: .atomic)
                #endif
            } catch {
                storageError = "Could not save translation changes. Your previous saved data is kept."
                return false
            }
        }
        self.records = records
        knownWords = words
        return true
    }

    private func persist(record: NativeTranslationRecord, key: NativeTranslationKey,
                         revisionKind: TranslationRevisionKind) throws {
        guard let contextStore else { return }
        let stored = try storedTranslation(
            record: record,
            key: key,
            revisionKind: revisionKind,
            knownWordsVersion: try contextStore.knownWordsVersion()
        )
        try contextStore.upsert(translation: stored)
    }

    private func storedTranslation(
        record: NativeTranslationRecord,
        key: NativeTranslationKey,
        revisionKind: TranslationRevisionKind,
        knownWordsVersion: Int
    ) throws -> StoredTranslation {
        guard let chatID = WhatsAppChatID(key.chatID), let messageID = WhatsAppMessageID(key.messageID) else {
            throw SQLiteContextPersistenceError.invalidStoredValue("translation.key")
        }
        let partsJSON: String?
        if Self.validParts(record.parts, original: record.original) {
            let partsData = try JSONEncoder().encode(record.parts)
            guard let encoded = String(data: partsData, encoding: .utf8) else {
                throw SQLiteContextPersistenceError.invalidStoredValue("translation.parts")
            }
            partsJSON = encoded
        } else {
            // Preserve the flattened text for old or incomplete records, but
            // omit alignment data unless it passes the same strict validator
            // used for new corrections and model output.
            partsJSON = nil
        }
        guard let stored = StoredTranslation(
            chatID: chatID,
            messageID: messageID,
            sourceLanguage: key.sourceLanguage,
            targetLanguage: key.targetLanguage,
            revision: max(1, record.revision),
            revisionKind: revisionKind,
            translatedBody: record.translatedText,
            sourceHash: Self.stableHash(record.original),
            contextHash: record.provenance?.contextHash
                ?? Self.stableHash("\(key.chatID)\u{0}\(key.messageID)"),
            promptVersion: record.provenance?.promptVersion ?? "native-review-v1",
            modelIdentifier: record.provenance?.modelIdentifier ?? "native-translation",
            knownWordsVersion: knownWordsVersion,
            contextMessageCount: record.provenance?.contextMessageCount ?? 0,
            summaryVersion: record.provenance?.summaryVersion,
            correctionComment: record.comment.isEmpty ? nil : record.comment,
            createdAt: Self.currentTimestamp(),
            sourceText: record.original,
            partsJSON: partsJSON
        ) else {
            throw SQLiteContextPersistenceError.invalidStoredValue("translation")
        }
        return stored
    }

    private static func storedKnownWord(from raw: String) -> StoredKnownWord? {
        guard let value = parseWordKey(raw) else { return nil }
        let now = currentTimestamp()
        return StoredKnownWord(
            language: value.language,
            normalizedText: value.normalizedText,
            displayText: value.normalizedText,
            createdAt: now,
            updatedAt: now
        )
    }

    private func inferredRevisionKind(for record: NativeTranslationRecord) -> TranslationRevisionKind {
        record.manuallyEdited ? .manualEdit : .model
    }

    private static func validParts(_ parts: [NativeTranslationPart], original: String) -> Bool {
        guard !parts.isEmpty, Set(parts.map(\.id)).count == parts.count,
              parts.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.translation.isEmpty })
        else { return false }

        var searchStart = original.startIndex
        for part in parts {
            guard let source = part.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty else { continue }
            guard let range = original.range(of: source, range: searchStart..<original.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return !parts.map(\.translation).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func records(from saved: [StoredTranslation]) -> [NativeTranslationKey: NativeTranslationRecord] {
        var result: [NativeTranslationKey: NativeTranslationRecord] = [:]
        for translation in saved.sorted(by: { $0.revision > $1.revision }) {
            let sourceLanguage = translation.sourceLanguage ?? "und"
            let key = NativeTranslationKey(
                chatID: translation.chatID.rawValue,
                messageID: translation.messageID.rawValue,
                sourceLanguage: sourceLanguage,
                targetLanguage: translation.targetLanguage
            )
            guard result[key] == nil, !translation.sourceText.isEmpty else { continue }
            let parts: [NativeTranslationPart]
            if let partsJSON = translation.partsJSON,
               let data = partsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([NativeTranslationPart].self, from: data),
               Self.validParts(decoded, original: translation.sourceText) {
                parts = decoded
            } else if !translation.translatedBody.isEmpty {
                // Old rows may not have alignment data. Keep their text but
                // expose no source mapping rather than inventing one.
                parts = [.init(id: "translation", source: nil, translation: translation.translatedBody)]
            } else {
                parts = []
            }
            result[key] = NativeTranslationRecord(
                original: translation.sourceText,
                parts: parts,
                revision: translation.revision,
                manuallyEdited: translation.revisionKind == .manualEdit,
                comment: translation.correctionComment ?? "",
                provenance: NativeTranslationProvenance(
                    contextHash: translation.contextHash,
                    promptVersion: translation.promptVersion,
                    modelIdentifier: translation.modelIdentifier,
                    contextMessageCount: translation.contextMessageCount,
                    summaryVersion: translation.summaryVersion
                )
            )
        }
        return result
    }

    private static func loadLegacySnapshot(from fileURL: URL) throws -> Snapshot {
        let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        guard saved.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return saved
    }

    private static func parseWordKey(_ raw: String) -> (language: String, normalizedText: String)? {
        guard let separator = raw.firstIndex(of: "\u{0}") else { return nil }
        let language = String(raw[..<separator])
        let normalized = String(raw[raw.index(after: separator)...])
        guard !language.isEmpty, !normalized.isEmpty else { return nil }
        return (language, normalized)
    }

    private static func currentTimestamp() -> WhatsAppTimestamp {
        // Date can only be negative before 1970; clamp for the persistence
        // schema's non-negative timestamp contract.
        let milliseconds = max(0, Int64(Date().timeIntervalSince1970 * 1_000))
        return WhatsAppTimestamp(millisecondsSince1970: milliseconds)!
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "fnv1a-%016llx", hash)
    }

    private struct Snapshot: Codable {
        let version: Int
        let records: [NativeTranslationKey: NativeTranslationRecord]
        let knownWords: Set<String>
    }
}
