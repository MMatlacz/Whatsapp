import Foundation

#if SWIFT_PACKAGE
import WhatsAppDomainCore
#endif

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

public enum TranslationRevisionKind: String, Equatable, Sendable {
    case model
    case retranslation
    case manualEdit = "manual_edit"
}

public struct StoredTranslation: Equatable, Sendable {
    public let chatID: WhatsAppChatID
    public let messageID: WhatsAppMessageID
    public let sourceLanguage: String?
    public let targetLanguage: String
    public let revision: Int
    public let revisionKind: TranslationRevisionKind
    public let translatedBody: String
    /// The exact source body is kept alongside the cache so a restored
    /// translation can still be matched to the message without guessing from
    /// a one-way hash.
    public let sourceText: String
    /// JSON encoded `NativeTranslationPart` values. PersistenceCore cannot
    /// depend on the app target, so this remains an opaque, validated payload.
    public let partsJSON: String?
    public let sourceHash: String
    public let contextHash: String
    public let promptVersion: String
    public let modelIdentifier: String
    public let knownWordsVersion: Int
    public let contextMessageCount: Int
    public let summaryVersion: Int?
    public let correctionComment: String?
    public let createdAt: WhatsAppTimestamp

    public init?(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        sourceLanguage: String?,
        targetLanguage: String,
        revision: Int,
        revisionKind: TranslationRevisionKind,
        translatedBody: String,
        sourceHash: String,
        contextHash: String,
        promptVersion: String,
        modelIdentifier: String,
        knownWordsVersion: Int,
        contextMessageCount: Int,
        summaryVersion: Int?,
        correctionComment: String?,
        createdAt: WhatsAppTimestamp,
        sourceText: String = "",
        partsJSON: String? = nil
    ) {
        if let sourceLanguage, sourceLanguage.trimmedPersistenceValue.isEmpty { return nil }
        if let correctionComment, correctionComment.trimmedPersistenceValue.isEmpty { return nil }
        if let partsJSON, partsJSON.trimmedPersistenceValue.isEmpty { return nil }
        guard
            !targetLanguage.trimmedPersistenceValue.isEmpty,
            revision > 0,
            !sourceHash.trimmedPersistenceValue.isEmpty,
            !contextHash.trimmedPersistenceValue.isEmpty,
            !promptVersion.trimmedPersistenceValue.isEmpty,
            !modelIdentifier.trimmedPersistenceValue.isEmpty,
            knownWordsVersion >= 0,
            contextMessageCount >= 0,
            summaryVersion.map({ $0 > 0 }) ?? true
        else { return nil }

        self.chatID = chatID
        self.messageID = messageID
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.revision = revision
        self.revisionKind = revisionKind
        self.translatedBody = translatedBody
        self.sourceText = sourceText
        self.partsJSON = partsJSON
        self.sourceHash = sourceHash
        self.contextHash = contextHash
        self.promptVersion = promptVersion
        self.modelIdentifier = modelIdentifier
        self.knownWordsVersion = knownWordsVersion
        self.contextMessageCount = contextMessageCount
        self.summaryVersion = summaryVersion
        self.correctionComment = correctionComment
        self.createdAt = createdAt
    }
}

public struct StoredVocabularyEntry: Equatable, Sendable {
    public let id: String
    public let chatID: WhatsAppChatID
    public let messageID: WhatsAppMessageID
    public let sourceLanguage: String
    public let targetLanguage: String
    public let translationRevision: Int
    public let sourceText: String
    public let normalizedSourceText: String
    public let contextualMeaning: String?
    public let literalMeaning: String?
    public let unavailableReason: String?
    public let contextHash: String
    public let createdAt: WhatsAppTimestamp
    public let updatedAt: WhatsAppTimestamp

    public init?(
        id: String,
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        sourceLanguage: String,
        targetLanguage: String,
        translationRevision: Int,
        sourceText: String,
        normalizedSourceText: String,
        contextualMeaning: String?,
        literalMeaning: String?,
        unavailableReason: String?,
        contextHash: String,
        createdAt: WhatsAppTimestamp,
        updatedAt: WhatsAppTimestamp
    ) {
        let explanations = [contextualMeaning, literalMeaning, unavailableReason].compactMap { $0 }
        guard
            !id.trimmedPersistenceValue.isEmpty,
            !sourceLanguage.trimmedPersistenceValue.isEmpty,
            !targetLanguage.trimmedPersistenceValue.isEmpty,
            translationRevision > 0,
            !sourceText.trimmedPersistenceValue.isEmpty,
            !normalizedSourceText.trimmedPersistenceValue.isEmpty,
            !contextHash.trimmedPersistenceValue.isEmpty,
            explanations.contains(where: { !$0.trimmedPersistenceValue.isEmpty }),
            updatedAt >= createdAt
        else { return nil }

        self.id = id
        self.chatID = chatID
        self.messageID = messageID
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.translationRevision = translationRevision
        self.sourceText = sourceText
        self.normalizedSourceText = normalizedSourceText
        self.contextualMeaning = contextualMeaning
        self.literalMeaning = literalMeaning
        self.unavailableReason = unavailableReason
        self.contextHash = contextHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StoredKnownWord: Equatable, Sendable {
    public let language: String
    public let normalizedText: String
    public let displayText: String
    public let createdAt: WhatsAppTimestamp
    public let updatedAt: WhatsAppTimestamp

    public init?(
        language: String,
        normalizedText: String,
        displayText: String,
        createdAt: WhatsAppTimestamp,
        updatedAt: WhatsAppTimestamp
    ) {
        guard
            !language.trimmedPersistenceValue.isEmpty,
            !normalizedText.trimmedPersistenceValue.isEmpty,
            !displayText.trimmedPersistenceValue.isEmpty,
            updatedAt >= createdAt
        else { return nil }
        self.language = language
        self.normalizedText = normalizedText
        self.displayText = displayText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StoredConversationSummary: Equatable, Sendable {
    public let chatID: WhatsAppChatID
    public let version: Int
    public let throughMessageID: WhatsAppMessageID
    public let throughTimestamp: WhatsAppTimestamp
    public let sourceMessageCount: Int
    public let contextHash: String
    public let summaryText: String
    public let promptVersion: String
    public let modelIdentifier: String
    public let createdAt: WhatsAppTimestamp

    public init?(
        chatID: WhatsAppChatID,
        version: Int,
        throughMessageID: WhatsAppMessageID,
        throughTimestamp: WhatsAppTimestamp,
        sourceMessageCount: Int,
        contextHash: String,
        summaryText: String,
        promptVersion: String,
        modelIdentifier: String,
        createdAt: WhatsAppTimestamp
    ) {
        guard
            version > 0,
            sourceMessageCount > 0,
            !contextHash.trimmedPersistenceValue.isEmpty,
            !summaryText.trimmedPersistenceValue.isEmpty,
            !promptVersion.trimmedPersistenceValue.isEmpty,
            !modelIdentifier.trimmedPersistenceValue.isEmpty
        else { return nil }
        self.chatID = chatID
        self.version = version
        self.throughMessageID = throughMessageID
        self.throughTimestamp = throughTimestamp
        self.sourceMessageCount = sourceMessageCount
        self.contextHash = contextHash
        self.summaryText = summaryText
        self.promptVersion = promptVersion
        self.modelIdentifier = modelIdentifier
        self.createdAt = createdAt
    }
}

public enum SQLiteContextPersistenceError: Error, Equatable, Sendable {
    case openFailed(String)
    case sqlite(code: Int32, message: String)
    case unsupportedSchemaVersion(Int32)
    case invalidArgument(String)
    case invalidStoredValue(String)
    case missingMessage(chatID: WhatsAppChatID, messageID: WhatsAppMessageID)
    case missingTranslation(chatID: WhatsAppChatID, messageID: WhatsAppMessageID, targetLanguage: String, revision: Int)
}

public final class SQLiteContextStore: @unchecked Sendable {
    public static let schemaVersion: Int32 = 2
    public let core: SQLiteWhatsAppStore

    private static let componentName = "translation_context"
    private let lock = NSLock()
    private var db: OpaquePointer?

    public init(path: String) throws {
        core = try SQLiteWhatsAppStore(path: path)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw SQLiteContextPersistenceError.openFailed(message)
        }

        db = handle
        do {
            try execute("PRAGMA foreign_keys = ON")
            _ = sqlite3_busy_timeout(handle, 5_000)
            try migrateIfNeeded()
        } catch {
            sqlite3_close(handle)
            db = nil
            throw error
        }
    }

    deinit {
        lock.lock()
        if let db { sqlite3_close(db) }
        db = nil
        lock.unlock()
    }

    public func currentSchemaVersion() throws -> Int32 {
        try locked { try componentVersion() }
    }

    public func upsert(translation: StoredTranslation) throws {
        try locked { try upsertTranslationUnlocked(translation) }
    }

    /// Imports a legacy translation snapshot as one SQLite transaction.
    ///
    /// The native model can still keep a legacy snapshot as a recovery copy,
    /// but it must never copy only the record that was most recently edited.
    /// A missing message, malformed value, or SQLite failure rolls back the
    /// complete import so a restart cannot expose a partially migrated state.
    public func importInitialState(
        translations: [StoredTranslation],
        knownWords: [StoredKnownWord]
    ) throws {
        try locked {
            try executeUnlocked("BEGIN IMMEDIATE")
            do {
                for translation in translations {
                    try upsertTranslationUnlocked(translation)
                }
                for knownWord in knownWords {
                    if try upsertKnownWordUnlocked(knownWord) {
                        try incrementKnownWordsVersion()
                    }
                }
                try executeUnlocked("COMMIT")
            } catch {
                try? executeUnlocked("ROLLBACK")
                throw error
            }
        }
    }

    private func upsertTranslationUnlocked(_ translation: StoredTranslation) throws {
        guard try messageExists(chatID: translation.chatID, messageID: translation.messageID) else {
            throw SQLiteContextPersistenceError.missingMessage(
                chatID: translation.chatID,
                messageID: translation.messageID
            )
        }

        let statement = try prepare(
            """
            INSERT INTO translations(
                chat_id, whatsapp_message_id, source_language, target_language, revision,
                revision_kind, translated_body, source_text, parts_json, source_hash,
                context_hash, prompt_version,
                model_id, known_words_version, context_message_count, summary_version,
                correction_comment, created_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chat_id, whatsapp_message_id, target_language, revision) DO UPDATE SET
                source_language = excluded.source_language,
                revision_kind = excluded.revision_kind,
                translated_body = excluded.translated_body,
                source_text = excluded.source_text,
                parts_json = excluded.parts_json,
                source_hash = excluded.source_hash,
                context_hash = excluded.context_hash,
                prompt_version = excluded.prompt_version,
                model_id = excluded.model_id,
                known_words_version = excluded.known_words_version,
                context_message_count = excluded.context_message_count,
                summary_version = excluded.summary_version,
                correction_comment = excluded.correction_comment,
                created_at_ms = excluded.created_at_ms
            """
        )
        defer { sqlite3_finalize(statement) }

        try bindText(translation.chatID.rawValue, at: 1, to: statement)
        try bindText(translation.messageID.rawValue, at: 2, to: statement)
        try bindOptionalText(translation.sourceLanguage, at: 3, to: statement)
        try bindText(translation.targetLanguage, at: 4, to: statement)
        try bindInt64(Int64(translation.revision), at: 5, to: statement)
        try bindText(translation.revisionKind.rawValue, at: 6, to: statement)
        try bindText(translation.translatedBody, at: 7, to: statement)
        try bindText(translation.sourceText, at: 8, to: statement)
        try bindOptionalText(translation.partsJSON, at: 9, to: statement)
        try bindText(translation.sourceHash, at: 10, to: statement)
        try bindText(translation.contextHash, at: 11, to: statement)
        try bindText(translation.promptVersion, at: 12, to: statement)
        try bindText(translation.modelIdentifier, at: 13, to: statement)
        try bindInt64(Int64(translation.knownWordsVersion), at: 14, to: statement)
        try bindInt64(Int64(translation.contextMessageCount), at: 15, to: statement)
        try bindOptionalInt64(translation.summaryVersion.map(Int64.init), at: 16, to: statement)
        try bindOptionalText(translation.correctionComment, at: 17, to: statement)
        try bindInt64(translation.createdAt.millisecondsSince1970, at: 18, to: statement)
        try stepDone(statement)
    }

    public func translation(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        targetLanguage: String,
        revision: Int
    ) throws -> StoredTranslation? {
        guard !targetLanguage.trimmedPersistenceValue.isEmpty, revision > 0 else {
            throw SQLiteContextPersistenceError.invalidArgument("translation key")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT chat_id, whatsapp_message_id, source_language, target_language, revision,
                       revision_kind, translated_body, source_text, parts_json, source_hash,
                       context_hash, prompt_version, model_id, known_words_version,
                       context_message_count, summary_version, correction_comment, created_at_ms
                FROM translations
                WHERE chat_id = ? AND whatsapp_message_id = ? AND target_language = ? AND revision = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindText(messageID.rawValue, at: 2, to: statement)
            try bindText(targetLanguage, at: 3, to: statement)
            try bindInt64(Int64(revision), at: 4, to: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            return try decodeTranslation(statement)
        }
    }

    public func latestTranslation(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        targetLanguage: String
    ) throws -> StoredTranslation? {
        guard !targetLanguage.trimmedPersistenceValue.isEmpty else {
            throw SQLiteContextPersistenceError.invalidArgument("targetLanguage")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT chat_id, whatsapp_message_id, source_language, target_language, revision,
                       revision_kind, translated_body, source_text, parts_json, source_hash,
                       context_hash, prompt_version, model_id, known_words_version,
                       context_message_count, summary_version, correction_comment, created_at_ms
                FROM translations
                WHERE chat_id = ? AND whatsapp_message_id = ? AND target_language = ?
                ORDER BY revision DESC
                LIMIT 1
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindText(messageID.rawValue, at: 2, to: statement)
            try bindText(targetLanguage, at: 3, to: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            return try decodeTranslation(statement)
        }
    }

    public func translations(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        targetLanguage: String,
        limit: Int = 100
    ) throws -> [StoredTranslation] {
        guard !targetLanguage.trimmedPersistenceValue.isEmpty, (1...100).contains(limit) else {
            throw SQLiteContextPersistenceError.invalidArgument("translation list")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT chat_id, whatsapp_message_id, source_language, target_language, revision,
                       revision_kind, translated_body, source_text, parts_json, source_hash,
                       context_hash, prompt_version, model_id, known_words_version,
                       context_message_count, summary_version, correction_comment, created_at_ms
                FROM translations
                WHERE chat_id = ? AND whatsapp_message_id = ? AND target_language = ?
                ORDER BY revision DESC
                LIMIT ?
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindText(messageID.rawValue, at: 2, to: statement)
            try bindText(targetLanguage, at: 3, to: statement)
            try bindInt64(Int64(limit), at: 4, to: statement)
            return try collect(statement, decode: decodeTranslation)
        }
    }

    /// Returns the persisted translation history across chats. The native
    /// model uses this on startup to restore the latest revision for each
    /// message without maintaining a second cache file.
    public func allTranslations(limit: Int = 10_000) throws -> [StoredTranslation] {
        guard (1...10_000).contains(limit) else {
            throw SQLiteContextPersistenceError.invalidArgument("translation history limit")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT chat_id, whatsapp_message_id, source_language, target_language, revision,
                       revision_kind, translated_body, source_text, parts_json, source_hash,
                       context_hash, prompt_version, model_id, known_words_version,
                       context_message_count, summary_version, correction_comment, created_at_ms
                FROM translations
                ORDER BY chat_id ASC, whatsapp_message_id ASC, target_language ASC, revision DESC
                LIMIT ?
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindInt64(Int64(limit), at: 1, to: statement)
            return try collect(statement, decode: decodeTranslation)
        }
    }

    public func deleteTranslation(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        targetLanguage: String,
        revision: Int
    ) throws {
        guard !targetLanguage.trimmedPersistenceValue.isEmpty, revision > 0 else {
            throw SQLiteContextPersistenceError.invalidArgument("translation key")
        }
        try locked {
            let statement = try prepare(
                "DELETE FROM translations WHERE chat_id = ? AND whatsapp_message_id = ? AND target_language = ? AND revision = ?"
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindText(messageID.rawValue, at: 2, to: statement)
            try bindText(targetLanguage, at: 3, to: statement)
            try bindInt64(Int64(revision), at: 4, to: statement)
            try stepDone(statement)
        }
    }

    public func upsert(vocabulary entry: StoredVocabularyEntry) throws {
        try locked {
            guard try translationExists(
                chatID: entry.chatID,
                messageID: entry.messageID,
                targetLanguage: entry.targetLanguage,
                revision: entry.translationRevision
            ) else {
                throw SQLiteContextPersistenceError.missingTranslation(
                    chatID: entry.chatID,
                    messageID: entry.messageID,
                    targetLanguage: entry.targetLanguage,
                    revision: entry.translationRevision
                )
            }

            let statement = try prepare(
                """
                INSERT INTO vocabulary_entries(
                    id, chat_id, whatsapp_message_id, source_language, target_language,
                    translation_revision, source_text, normalized_source_text, contextual_meaning,
                    literal_meaning, unavailable_reason, context_hash, created_at_ms, updated_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    chat_id = excluded.chat_id,
                    whatsapp_message_id = excluded.whatsapp_message_id,
                    source_language = excluded.source_language,
                    target_language = excluded.target_language,
                    translation_revision = excluded.translation_revision,
                    source_text = excluded.source_text,
                    normalized_source_text = excluded.normalized_source_text,
                    contextual_meaning = excluded.contextual_meaning,
                    literal_meaning = excluded.literal_meaning,
                    unavailable_reason = excluded.unavailable_reason,
                    context_hash = excluded.context_hash,
                    updated_at_ms = excluded.updated_at_ms
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(entry.id, at: 1, to: statement)
            try bindText(entry.chatID.rawValue, at: 2, to: statement)
            try bindText(entry.messageID.rawValue, at: 3, to: statement)
            try bindText(entry.sourceLanguage, at: 4, to: statement)
            try bindText(entry.targetLanguage, at: 5, to: statement)
            try bindInt64(Int64(entry.translationRevision), at: 6, to: statement)
            try bindText(entry.sourceText, at: 7, to: statement)
            try bindText(entry.normalizedSourceText, at: 8, to: statement)
            try bindOptionalText(entry.contextualMeaning, at: 9, to: statement)
            try bindOptionalText(entry.literalMeaning, at: 10, to: statement)
            try bindOptionalText(entry.unavailableReason, at: 11, to: statement)
            try bindText(entry.contextHash, at: 12, to: statement)
            try bindInt64(entry.createdAt.millisecondsSince1970, at: 13, to: statement)
            try bindInt64(entry.updatedAt.millisecondsSince1970, at: 14, to: statement)
            try stepDone(statement)
        }
    }

    public func vocabularyEntries(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        targetLanguage: String,
        translationRevision: Int
    ) throws -> [StoredVocabularyEntry] {
        guard !targetLanguage.trimmedPersistenceValue.isEmpty, translationRevision > 0 else {
            throw SQLiteContextPersistenceError.invalidArgument("vocabulary key")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT id, chat_id, whatsapp_message_id, source_language, target_language,
                       translation_revision, source_text, normalized_source_text, contextual_meaning,
                       literal_meaning, unavailable_reason, context_hash, created_at_ms, updated_at_ms
                FROM vocabulary_entries
                WHERE chat_id = ? AND whatsapp_message_id = ? AND target_language = ? AND translation_revision = ?
                ORDER BY normalized_source_text ASC, id ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindText(messageID.rawValue, at: 2, to: statement)
            try bindText(targetLanguage, at: 3, to: statement)
            try bindInt64(Int64(translationRevision), at: 4, to: statement)
            return try collect(statement, decode: decodeVocabulary)
        }
    }

    public func deleteVocabularyEntry(id: String) throws {
        guard !id.trimmedPersistenceValue.isEmpty else {
            throw SQLiteContextPersistenceError.invalidArgument("vocabulary.id")
        }
        try locked {
            let statement = try prepare("DELETE FROM vocabulary_entries WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bindText(id, at: 1, to: statement)
            try stepDone(statement)
        }
    }

    public func upsert(knownWord: StoredKnownWord) throws {
        try locked {
            try executeUnlocked("BEGIN IMMEDIATE")
            do {
                if try upsertKnownWordUnlocked(knownWord) {
                    try incrementKnownWordsVersion()
                }
                try executeUnlocked("COMMIT")
            } catch {
                try? executeUnlocked("ROLLBACK")
                throw error
            }
        }
    }

    private func upsertKnownWordUnlocked(_ knownWord: StoredKnownWord) throws -> Bool {
        let statement = try prepare(
            """
            INSERT INTO known_words(language, normalized_text, display_text, created_at_ms, updated_at_ms)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(language, normalized_text) DO UPDATE SET
                display_text = excluded.display_text,
                updated_at_ms = excluded.updated_at_ms
            WHERE excluded.updated_at_ms >= known_words.updated_at_ms
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(knownWord.language, at: 1, to: statement)
        try bindText(knownWord.normalizedText, at: 2, to: statement)
        try bindText(knownWord.displayText, at: 3, to: statement)
        try bindInt64(knownWord.createdAt.millisecondsSince1970, at: 4, to: statement)
        try bindInt64(knownWord.updatedAt.millisecondsSince1970, at: 5, to: statement)
        try stepDone(statement)
        guard let db else { return false }
        return sqlite3_changes(db) > 0
    }

    public func knownWords(language: String, limit: Int = 500) throws -> [StoredKnownWord] {
        guard !language.trimmedPersistenceValue.isEmpty, (1...500).contains(limit) else {
            throw SQLiteContextPersistenceError.invalidArgument("knownWords")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT language, normalized_text, display_text, created_at_ms, updated_at_ms
                FROM known_words
                WHERE language = ?
                ORDER BY normalized_text ASC
                LIMIT ?
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(language, at: 1, to: statement)
            try bindInt64(Int64(limit), at: 2, to: statement)
            return try collect(statement, decode: decodeKnownWord)
        }
    }

    public func allKnownWords(limit: Int = 5_000) throws -> [StoredKnownWord] {
        guard (1...5_000).contains(limit) else {
            throw SQLiteContextPersistenceError.invalidArgument("known words history limit")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT language, normalized_text, display_text, created_at_ms, updated_at_ms
                FROM known_words
                ORDER BY language ASC, normalized_text ASC
                LIMIT ?
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindInt64(Int64(limit), at: 1, to: statement)
            return try collect(statement, decode: decodeKnownWord)
        }
    }

    public func knownWordsVersion() throws -> Int {
        try locked {
            let statement = try prepare("SELECT version FROM known_word_state WHERE singleton = 1")
            defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            let value = sqlite3_column_int64(statement, 0)
            guard value >= 0, value <= Int64(Int.max) else {
                throw SQLiteContextPersistenceError.invalidStoredValue("known_word_state.version")
            }
            return Int(value)
        }
    }

    public func deleteKnownWord(language: String, normalizedText: String) throws {
        guard !language.trimmedPersistenceValue.isEmpty, !normalizedText.trimmedPersistenceValue.isEmpty else {
            throw SQLiteContextPersistenceError.invalidArgument("knownWord key")
        }
        try locked {
            try executeUnlocked("BEGIN IMMEDIATE")
            do {
                let statement = try prepare("DELETE FROM known_words WHERE language = ? AND normalized_text = ?")
                defer { sqlite3_finalize(statement) }
                try bindText(language, at: 1, to: statement)
                try bindText(normalizedText, at: 2, to: statement)
                try stepDone(statement)
                if let db, sqlite3_changes(db) > 0 {
                    try incrementKnownWordsVersion()
                }
                try executeUnlocked("COMMIT")
            } catch {
                try? executeUnlocked("ROLLBACK")
                throw error
            }
        }
    }

    public func upsert(summary: StoredConversationSummary) throws {
        try locked {
            guard try messageExists(chatID: summary.chatID, messageID: summary.throughMessageID) else {
                throw SQLiteContextPersistenceError.missingMessage(
                    chatID: summary.chatID,
                    messageID: summary.throughMessageID
                )
            }
            let statement = try prepare(
                """
                INSERT INTO conversation_summaries(
                    chat_id, version, through_message_id, through_timestamp_ms, source_message_count,
                    context_hash, summary_text, prompt_version, model_id, created_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(chat_id, version) DO UPDATE SET
                    through_message_id = excluded.through_message_id,
                    through_timestamp_ms = excluded.through_timestamp_ms,
                    source_message_count = excluded.source_message_count,
                    context_hash = excluded.context_hash,
                    summary_text = excluded.summary_text,
                    prompt_version = excluded.prompt_version,
                    model_id = excluded.model_id,
                    created_at_ms = excluded.created_at_ms
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(summary.chatID.rawValue, at: 1, to: statement)
            try bindInt64(Int64(summary.version), at: 2, to: statement)
            try bindText(summary.throughMessageID.rawValue, at: 3, to: statement)
            try bindInt64(summary.throughTimestamp.millisecondsSince1970, at: 4, to: statement)
            try bindInt64(Int64(summary.sourceMessageCount), at: 5, to: statement)
            try bindText(summary.contextHash, at: 6, to: statement)
            try bindText(summary.summaryText, at: 7, to: statement)
            try bindText(summary.promptVersion, at: 8, to: statement)
            try bindText(summary.modelIdentifier, at: 9, to: statement)
            try bindInt64(summary.createdAt.millisecondsSince1970, at: 10, to: statement)
            try stepDone(statement)
        }
    }

    public func latestSummary(chatID: WhatsAppChatID) throws -> StoredConversationSummary? {
        try locked {
            let statement = try prepare(
                """
                SELECT chat_id, version, through_message_id, through_timestamp_ms, source_message_count,
                       context_hash, summary_text, prompt_version, model_id, created_at_ms
                FROM conversation_summaries
                WHERE chat_id = ?
                ORDER BY version DESC
                LIMIT 1
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            return try decodeSummary(statement)
        }
    }

    public func summaries(chatID: WhatsAppChatID, limit: Int = 100) throws -> [StoredConversationSummary] {
        guard (1...100).contains(limit) else {
            throw SQLiteContextPersistenceError.invalidArgument("summary limit")
        }
        return try locked {
            let statement = try prepare(
                """
                SELECT chat_id, version, through_message_id, through_timestamp_ms, source_message_count,
                       context_hash, summary_text, prompt_version, model_id, created_at_ms
                FROM conversation_summaries
                WHERE chat_id = ?
                ORDER BY version DESC
                LIMIT ?
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindInt64(Int64(limit), at: 2, to: statement)
            return try collect(statement, decode: decodeSummary)
        }
    }

    public func deleteSummaries(chatID: WhatsAppChatID) throws {
        try locked {
            let statement = try prepare("DELETE FROM conversation_summaries WHERE chat_id = ?")
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try stepDone(statement)
        }
    }

    private func migrateIfNeeded() throws {
        try locked {
            try executeUnlocked("BEGIN IMMEDIATE")
            do {
                try executeUnlocked(
                    """
                    CREATE TABLE IF NOT EXISTS persistence_component_versions(
                        component TEXT PRIMARY KEY NOT NULL,
                        version INTEGER NOT NULL CHECK(version >= 0)
                    )
                    """
                )
                let version = try componentVersion()
                guard version <= Self.schemaVersion else {
                    throw SQLiteContextPersistenceError.unsupportedSchemaVersion(version)
                }
                if version < 1 { try applyMigration1() }
                if version < 2 { try applyMigration2() }
                try setComponentVersion(Self.schemaVersion)
                try executeUnlocked("COMMIT")
            } catch {
                try? executeUnlocked("ROLLBACK")
                throw error
            }
        }
    }

    private func applyMigration1() throws {
        try executeUnlocked(
            """
            CREATE TABLE IF NOT EXISTS translations(
                chat_id TEXT NOT NULL,
                whatsapp_message_id TEXT NOT NULL,
                source_language TEXT NULL,
                target_language TEXT NOT NULL,
                revision INTEGER NOT NULL CHECK(revision > 0),
                revision_kind TEXT NOT NULL CHECK(revision_kind IN ('model', 'retranslation', 'manual_edit')),
                translated_body TEXT NOT NULL,
                source_text TEXT NOT NULL DEFAULT '',
                parts_json TEXT NULL,
                source_hash TEXT NOT NULL,
                context_hash TEXT NOT NULL,
                prompt_version TEXT NOT NULL,
                model_id TEXT NOT NULL,
                known_words_version INTEGER NOT NULL CHECK(known_words_version >= 0),
                context_message_count INTEGER NOT NULL CHECK(context_message_count >= 0),
                summary_version INTEGER NULL CHECK(summary_version IS NULL OR summary_version > 0),
                correction_comment TEXT NULL,
                created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                PRIMARY KEY(chat_id, whatsapp_message_id, target_language, revision),
                FOREIGN KEY(chat_id, whatsapp_message_id)
                    REFERENCES messages(chat_id, whatsapp_message_id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS translations_latest
            ON translations(chat_id, whatsapp_message_id, target_language, revision DESC);

            CREATE TABLE IF NOT EXISTS vocabulary_entries(
                id TEXT PRIMARY KEY NOT NULL,
                chat_id TEXT NOT NULL,
                whatsapp_message_id TEXT NOT NULL,
                source_language TEXT NOT NULL,
                target_language TEXT NOT NULL,
                translation_revision INTEGER NOT NULL CHECK(translation_revision > 0),
                source_text TEXT NOT NULL,
                normalized_source_text TEXT NOT NULL,
                contextual_meaning TEXT NULL,
                literal_meaning TEXT NULL,
                unavailable_reason TEXT NULL,
                context_hash TEXT NOT NULL,
                created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= created_at_ms),
                CHECK(contextual_meaning IS NOT NULL OR literal_meaning IS NOT NULL OR unavailable_reason IS NOT NULL),
                FOREIGN KEY(chat_id, whatsapp_message_id, target_language, translation_revision)
                    REFERENCES translations(chat_id, whatsapp_message_id, target_language, revision) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS vocabulary_by_message_revision
            ON vocabulary_entries(
                chat_id, whatsapp_message_id, target_language, translation_revision,
                normalized_source_text, id
            );

            CREATE TABLE IF NOT EXISTS known_words(
                language TEXT NOT NULL,
                normalized_text TEXT NOT NULL,
                display_text TEXT NOT NULL,
                created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                updated_at_ms INTEGER NOT NULL CHECK(updated_at_ms >= created_at_ms),
                PRIMARY KEY(language, normalized_text)
            );

            CREATE INDEX IF NOT EXISTS known_words_by_language
            ON known_words(language, normalized_text);

            CREATE TABLE IF NOT EXISTS known_word_state(
                singleton INTEGER PRIMARY KEY NOT NULL CHECK(singleton = 1),
                version INTEGER NOT NULL CHECK(version >= 0)
            );

            INSERT OR IGNORE INTO known_word_state(singleton, version) VALUES (1, 0);

            CREATE TABLE IF NOT EXISTS conversation_summaries(
                chat_id TEXT NOT NULL,
                version INTEGER NOT NULL CHECK(version > 0),
                through_message_id TEXT NOT NULL,
                through_timestamp_ms INTEGER NOT NULL CHECK(through_timestamp_ms >= 0),
                source_message_count INTEGER NOT NULL CHECK(source_message_count > 0),
                context_hash TEXT NOT NULL,
                summary_text TEXT NOT NULL,
                prompt_version TEXT NOT NULL,
                model_id TEXT NOT NULL,
                created_at_ms INTEGER NOT NULL CHECK(created_at_ms >= 0),
                PRIMARY KEY(chat_id, version),
                FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE,
                FOREIGN KEY(chat_id, through_message_id)
                    REFERENCES messages(chat_id, whatsapp_message_id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS conversation_summaries_latest
            ON conversation_summaries(chat_id, version DESC);
            """
        )
    }

    private func applyMigration2() throws {
        // Version 1 stored only a one-way source hash and a flattened
        // translation. Add the exact source and opaque structured parts so
        // startup can restore records and safe source-to-translation mappings.
        if try !tableHasColumn(table: "translations", column: "source_text") {
            try executeUnlocked("ALTER TABLE translations ADD COLUMN source_text TEXT NOT NULL DEFAULT ''")
        }
        if try !tableHasColumn(table: "translations", column: "parts_json") {
            try executeUnlocked("ALTER TABLE translations ADD COLUMN parts_json TEXT NULL")
        }
    }

    private func tableHasColumn(table: String, column: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return false }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            if columnText(statement, at: 1) == column { return true }
        }
    }

    private func componentVersion() throws -> Int32 {
        let statement = try prepare("SELECT version FROM persistence_component_versions WHERE component = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(Self.componentName, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return 0 }
        guard result == SQLITE_ROW else { throw sqliteError(code: result) }
        let value = sqlite3_column_int64(statement, 0)
        guard value >= 0, value <= Int64(Int32.max) else {
            throw SQLiteContextPersistenceError.invalidStoredValue("persistence_component_versions.version")
        }
        return Int32(value)
    }

    private func setComponentVersion(_ version: Int32) throws {
        let statement = try prepare(
            """
            INSERT INTO persistence_component_versions(component, version) VALUES (?, ?)
            ON CONFLICT(component) DO UPDATE SET version = excluded.version
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(Self.componentName, at: 1, to: statement)
        try bindInt64(Int64(version), at: 2, to: statement)
        try stepDone(statement)
    }

    private func messageExists(chatID: WhatsAppChatID, messageID: WhatsAppMessageID) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM messages WHERE chat_id = ? AND whatsapp_message_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bindText(chatID.rawValue, at: 1, to: statement)
        try bindText(messageID.rawValue, at: 2, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw sqliteError(code: result)
    }

    private func translationExists(
        chatID: WhatsAppChatID,
        messageID: WhatsAppMessageID,
        targetLanguage: String,
        revision: Int
    ) throws -> Bool {
        let statement = try prepare(
            """
            SELECT 1 FROM translations
            WHERE chat_id = ? AND whatsapp_message_id = ? AND target_language = ? AND revision = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(chatID.rawValue, at: 1, to: statement)
        try bindText(messageID.rawValue, at: 2, to: statement)
        try bindText(targetLanguage, at: 3, to: statement)
        try bindInt64(Int64(revision), at: 4, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw sqliteError(code: result)
    }

    private func incrementKnownWordsVersion() throws {
        try executeUnlocked("UPDATE known_word_state SET version = version + 1 WHERE singleton = 1")
    }

    private func decodeTranslation(_ statement: OpaquePointer) throws -> StoredTranslation {
        guard
            let chatID = columnText(statement, at: 0).flatMap { WhatsAppChatID($0) },
            let messageID = columnText(statement, at: 1).flatMap { WhatsAppMessageID($0) },
            let targetLanguage = columnText(statement, at: 3),
            let rawKind = columnText(statement, at: 5),
            let kind = TranslationRevisionKind(rawValue: rawKind),
            let translatedBody = columnText(statement, at: 6),
            let sourceHash = columnText(statement, at: 9),
            let contextHash = columnText(statement, at: 10),
            let promptVersion = columnText(statement, at: 11),
            let modelID = columnText(statement, at: 12),
            let createdAt = timestamp(statement, at: 17)
        else { throw SQLiteContextPersistenceError.invalidStoredValue("translations") }

        let revision = try positiveInt(statement, at: 4, field: "translations.revision")
        let knownVersion = try nonNegativeInt(statement, at: 13, field: "translations.known_words_version")
        let contextCount = try nonNegativeInt(statement, at: 14, field: "translations.context_message_count")
        let summaryVersion = try optionalPositiveInt(statement, at: 15, field: "translations.summary_version")

        guard let value = StoredTranslation(
            chatID: chatID,
            messageID: messageID,
            sourceLanguage: columnText(statement, at: 2),
            targetLanguage: targetLanguage,
            revision: revision,
            revisionKind: kind,
            translatedBody: translatedBody,
            sourceHash: sourceHash,
            contextHash: contextHash,
            promptVersion: promptVersion,
            modelIdentifier: modelID,
            knownWordsVersion: knownVersion,
            contextMessageCount: contextCount,
            summaryVersion: summaryVersion,
            correctionComment: columnText(statement, at: 16),
            createdAt: createdAt,
            sourceText: columnText(statement, at: 7) ?? "",
            partsJSON: columnText(statement, at: 8)
        ) else { throw SQLiteContextPersistenceError.invalidStoredValue("translations") }
        return value
    }

    private func decodeVocabulary(_ statement: OpaquePointer) throws -> StoredVocabularyEntry {
        guard
            let id = columnText(statement, at: 0),
            let chatID = columnText(statement, at: 1).flatMap { WhatsAppChatID($0) },
            let messageID = columnText(statement, at: 2).flatMap { WhatsAppMessageID($0) },
            let sourceLanguage = columnText(statement, at: 3),
            let targetLanguage = columnText(statement, at: 4),
            let sourceText = columnText(statement, at: 6),
            let normalizedSourceText = columnText(statement, at: 7),
            let contextHash = columnText(statement, at: 11),
            let createdAt = timestamp(statement, at: 12),
            let updatedAt = timestamp(statement, at: 13)
        else { throw SQLiteContextPersistenceError.invalidStoredValue("vocabulary_entries") }
        let revision = try positiveInt(statement, at: 5, field: "vocabulary_entries.translation_revision")

        guard let value = StoredVocabularyEntry(
            id: id,
            chatID: chatID,
            messageID: messageID,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translationRevision: revision,
            sourceText: sourceText,
            normalizedSourceText: normalizedSourceText,
            contextualMeaning: columnText(statement, at: 8),
            literalMeaning: columnText(statement, at: 9),
            unavailableReason: columnText(statement, at: 10),
            contextHash: contextHash,
            createdAt: createdAt,
            updatedAt: updatedAt
        ) else { throw SQLiteContextPersistenceError.invalidStoredValue("vocabulary_entries") }
        return value
    }

    private func decodeKnownWord(_ statement: OpaquePointer) throws -> StoredKnownWord {
        guard
            let language = columnText(statement, at: 0),
            let normalized = columnText(statement, at: 1),
            let display = columnText(statement, at: 2),
            let createdAt = timestamp(statement, at: 3),
            let updatedAt = timestamp(statement, at: 4),
            let value = StoredKnownWord(
                language: language,
                normalizedText: normalized,
                displayText: display,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        else { throw SQLiteContextPersistenceError.invalidStoredValue("known_words") }
        return value
    }

    private func decodeSummary(_ statement: OpaquePointer) throws -> StoredConversationSummary {
        guard
            let chatID = columnText(statement, at: 0).flatMap { WhatsAppChatID($0) },
            let messageID = columnText(statement, at: 2).flatMap { WhatsAppMessageID($0) },
            let throughTimestamp = timestamp(statement, at: 3),
            let contextHash = columnText(statement, at: 5),
            let summaryText = columnText(statement, at: 6),
            let promptVersion = columnText(statement, at: 7),
            let modelID = columnText(statement, at: 8),
            let createdAt = timestamp(statement, at: 9)
        else { throw SQLiteContextPersistenceError.invalidStoredValue("conversation_summaries") }
        let version = try positiveInt(statement, at: 1, field: "conversation_summaries.version")
        let count = try positiveInt(statement, at: 4, field: "conversation_summaries.source_message_count")

        guard let value = StoredConversationSummary(
            chatID: chatID,
            version: version,
            throughMessageID: messageID,
            throughTimestamp: throughTimestamp,
            sourceMessageCount: count,
            contextHash: contextHash,
            summaryText: summaryText,
            promptVersion: promptVersion,
            modelIdentifier: modelID,
            createdAt: createdAt
        ) else { throw SQLiteContextPersistenceError.invalidStoredValue("conversation_summaries") }
        return value
    }

    private func timestamp(_ statement: OpaquePointer, at index: Int32) -> WhatsAppTimestamp? {
        WhatsAppTimestamp(millisecondsSince1970: sqlite3_column_int64(statement, index))
    }

    private func positiveInt(_ statement: OpaquePointer, at index: Int32, field: String) throws -> Int {
        let value = sqlite3_column_int64(statement, index)
        guard value > 0, value <= Int64(Int.max) else {
            throw SQLiteContextPersistenceError.invalidStoredValue(field)
        }
        return Int(value)
    }

    private func nonNegativeInt(_ statement: OpaquePointer, at index: Int32, field: String) throws -> Int {
        let value = sqlite3_column_int64(statement, index)
        guard value >= 0, value <= Int64(Int.max) else {
            throw SQLiteContextPersistenceError.invalidStoredValue(field)
        }
        return Int(value)
    }

    private func optionalPositiveInt(_ statement: OpaquePointer, at index: Int32, field: String) throws -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return try positiveInt(statement, at: index, field: field)
    }

    private func collect<T>(_ statement: OpaquePointer, decode: (OpaquePointer) throws -> T) throws -> [T] {
        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return values }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            values.append(try decode(statement))
        }
    }

    private func execute(_ sql: String) throws {
        try locked { try executeUnlocked(sql) }
    }

    private func executeUnlocked(_ sql: String) throws {
        guard let db else { throw SQLiteContextPersistenceError.openFailed("closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLiteContextPersistenceError.sqlite(code: result, message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw SQLiteContextPersistenceError.openFailed("closed") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw sqliteError(code: result) }
        return statement
    }

    private func bindText(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, contextSQLiteTransient)
        guard result == SQLITE_OK else { throw sqliteError(code: result) }
    }

    private func bindOptionalText(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        if let value {
            try bindText(value, at: index, to: statement)
        } else {
            let result = sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else { throw sqliteError(code: result) }
        }
    }

    private func bindInt64(_ value: Int64, at index: Int32, to statement: OpaquePointer) throws {
        let result = sqlite3_bind_int64(statement, index, value)
        guard result == SQLITE_OK else { throw sqliteError(code: result) }
    }

    private func bindOptionalInt64(_ value: Int64?, at index: Int32, to statement: OpaquePointer) throws {
        if let value {
            try bindInt64(value, at: index, to: statement)
        } else {
            let result = sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else { throw sqliteError(code: result) }
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw sqliteError(code: result) }
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: text)
    }

    private func sqliteError(code: Int32) -> SQLiteContextPersistenceError {
        guard let db else { return .sqlite(code: code, message: "closed") }
        return .sqlite(code: code, message: String(cString: sqlite3_errmsg(db)))
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private extension String {
    var trimmedPersistenceValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private let contextSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
