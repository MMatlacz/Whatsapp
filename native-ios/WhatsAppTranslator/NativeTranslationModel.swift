import Foundation
import Observation
#if SWIFT_PACKAGE
import PersistenceCore
import WhatsAppDomainCore
#endif

struct NativeTranslationKey: Hashable, Codable, Sendable {
    let chatID: String
    let messageID: String
    let sourceLanguage: String
    let targetLanguage: String
}

struct NativeTranslationPart: Equatable, Codable, Identifiable, Sendable {
    let id: String
    let source: String?
    var translation: String
}

struct NativeTranslationRecord: Equatable, Codable, Sendable {
    let original: String
    var parts: [NativeTranslationPart]
    var revision = 1
    var manuallyEdited = false
    var comment = ""
    var isSample = false

    var translatedText: String { parts.map(\.translation).joined() }
}

struct NativeRetranslationRequest: Equatable, Sendable {
    let key: NativeTranslationKey
    let original: String
    let previousTranslation: String
    let comment: String
    let revision: Int
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
    private(set) var notices: [NativeTranslationKey: String] = [:]
    private(set) var storageError: String?
    var showKnownWords = false
    var experimentalTranslationEnabled = false
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let retranslator: (any NativeRetranslator)?
    @ObservationIgnored private let contextStore: SQLiteContextStore?

    init(fileURL: URL? = nil, retranslator: (any NativeRetranslator)? = nil,
         contextStore: SQLiteContextStore? = nil) {
        self.fileURL = fileURL
        self.retranslator = retranslator
        self.contextStore = contextStore

        var loadedDatabase = false
        if let contextStore {
            do {
                let saved = try contextStore.allTranslations()
                records = Self.records(from: saved)
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
            model.storageError = "SQLite translation storage is unavailable. Translation changes are disabled."
            return model
        }

        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let contextStore = try SQLiteContextStore(path: databaseURL.path)
            return NativeTranslationModel(fileURL: legacyURL, retranslator: retranslator,
                                          contextStore: contextStore)
        } catch {
            // Keep the legacy file available for recovery, but expose the
            // database failure instead of silently pretending SQLite opened.
            let model = NativeTranslationModel(fileURL: legacyURL, retranslator: retranslator)
            model.storageError = "SQLite translation storage is unavailable. Translation changes are disabled."
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
            manuallyEdited: true, comment: current?.comment ?? "", isSample: current?.isSample ?? false
        )
        guard commit(records: updated, words: knownWords, changedKey: key, revisionKind: .manualEdit) else {
            return false
        }
        notices[key] = "Manual correction saved locally. Original message unchanged."
        return true
    }

    func retranslate(key: NativeTranslationKey, original: String, comment: String) async {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !running.contains(key) else { return }
        var current = record(for: key, original: original)
            ?? NativeTranslationRecord(original: original, parts: [], revision: 0)
        current.comment = trimmed
        // Increment even for a saved request so an older in-flight result cannot overwrite it.
        current.revision += 1
        var updated = records
        updated[key] = current
        // A comment-only save must keep the manual-correction provenance. If
        // an engine later succeeds, the resulting revision is recorded as a
        // retranslation and clears that flag.
        let pendingKind: TranslationRevisionKind = current.manuallyEdited ? .manualEdit : .retranslation
        guard commit(records: updated, words: knownWords, changedKey: key, revisionKind: pendingKind) else {
            return
        }
        guard let retranslator, retranslator.isValidated else {
            notices[key] = "Comment saved. Retranslation is blocked until a validated translation engine is enabled. No model was run."
            return
        }
        let revision = current.revision
        running.insert(key)
        defer { running.remove(key) }
        do {
            let parts = try await retranslator.retranslate(.init(
                key: key, original: original, previousTranslation: current.translatedText,
                comment: trimmed, revision: revision
            ))
            guard records[key]?.revision == revision, records[key]?.original == original else { return }
            guard Self.validParts(parts, original: original) else {
                notices[key] = "The translation result was invalid. Your previous translation is kept."
                return
            }
            current.parts = parts
            current.manuallyEdited = false
            current.revision += 1
            updated = records
            updated[key] = current
            let kind: TranslationRevisionKind = current.parts.isEmpty ? .retranslation :
                (records[key]?.parts.isEmpty == true ? .model : .retranslation)
            if commit(records: updated, words: knownWords, changedKey: key, revisionKind: kind) {
                notices[key] = "Retranslation updated."
            }
        } catch {
            guard records[key]?.revision == revision else { return }
            notices[key] = "Retranslation failed. Your previous translation and comment are kept."
        }
    }

    func translate(key: NativeTranslationKey, original: String) async {
        guard experimentalTranslationEnabled else {
            notices[key] = "Automatic translation is disabled until a validated engine passes quality and resource review."
            return
        }
        guard let retranslator, retranslator.isValidated else {
            notices[key] = "No validated local translation model is installed and configured. No model was run."
            return
        }
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record(for: key, original: original)?.parts.isEmpty != false else { return }
        await retranslate(key: key, original: original,
                          comment: "Translate faithfully. Preserve meaning, tone and quoted references.")
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
            contextHash: Self.stableHash("\(key.chatID)\u{0}\(key.messageID)"),
            promptVersion: "native-review-v1",
            modelIdentifier: "native-translation",
            knownWordsVersion: knownWordsVersion,
            contextMessageCount: 0,
            summaryVersion: nil,
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
                comment: translation.correctionComment ?? ""
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
