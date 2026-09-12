import Foundation
import Observation

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
    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart]
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
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let retranslator: (any NativeRetranslator)?

    init(fileURL: URL? = nil, retranslator: (any NativeRetranslator)? = nil) {
        self.fileURL = fileURL
        self.retranslator = retranslator
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
            guard saved.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            records = saved.records
            knownWords = saved.knownWords
        } catch { storageError = "Saved translation edits could not be read. The file has not been overwritten." }
    }

    static func applicationStore() -> NativeTranslationModel {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return NativeTranslationModel(fileURL: directory?
            .appendingPathComponent("NativeTranslationEdits", isDirectory: true)
            .appendingPathComponent("edits-v1.json"))
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
        knownWords.contains(wordKey(source, language: language))
    }

    func toggleKnown(_ source: String, language: String) {
        let word = wordKey(source, language: language)
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
        var updated = records
        updated[key] = NativeTranslationRecord(
            original: original, parts: parts, revision: expectedRevision + 1,
            manuallyEdited: true, comment: current?.comment ?? "", isSample: current?.isSample ?? false
        )
        guard commit(records: updated, words: knownWords) else { return false }
        notices[key] = "Manual correction saved locally. Original message unchanged."
        return true
    }

    func retranslate(key: NativeTranslationKey, original: String, comment: String) async {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !running.contains(key) else { return }
        var current = record(for: key, original: original)
            ?? NativeTranslationRecord(original: original, parts: [], revision: 0)
        current.comment = trimmed
        // Increment even for a saved request so an older in-flight result cannot overwrite it.
        current.revision += 1
        var updated = records
        updated[key] = current
        guard commit(records: updated, words: knownWords) else { return }
        guard let retranslator else {
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
            guard !parts.map(\.translation).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(parts.map(\.id)).count == parts.count,
                  parts.allSatisfy({ $0.source == nil || original.contains($0.source ?? "") }) else {
                notices[key] = "The translation result was invalid. Your previous translation is kept."
                return
            }
            current.parts = parts
            current.manuallyEdited = false
            current.revision += 1
            updated = records
            updated[key] = current
            if commit(records: updated, words: knownWords) { notices[key] = "Retranslation updated." }
        } catch {
            guard records[key]?.revision == revision else { return }
            notices[key] = "Retranslation failed. Your previous translation and comment are kept."
        }
    }

    private func wordKey(_ word: String, language: String) -> String {
        language.lowercased() + "\u{0}" + word.precomposedStringWithCanonicalMapping.lowercased()
    }

    @discardableResult
    private func commit(records: [NativeTranslationKey: NativeTranslationRecord], words: Set<String>) -> Bool {
        guard storageError == nil else { return false }
        if let fileURL {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
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

    private struct Snapshot: Codable {
        let version: Int
        let records: [NativeTranslationKey: NativeTranslationRecord]
        let knownWords: Set<String>
    }
}
