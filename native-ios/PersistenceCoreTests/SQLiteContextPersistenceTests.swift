import Foundation
import XCTest
import CSQLite
@testable import PersistenceCore
import WhatsAppDomainCore

final class SQLiteContextPersistenceTests: XCTestCase {
    func testMigratesExistingCoreDatabaseWithoutChangingCoreSchemaVersion() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let ids = try seedCoreDatabase(at: url)

        let contextStore = try SQLiteContextStore(path: url.path)

        XCTAssertEqual(try contextStore.currentSchemaVersion(), 1)
        XCTAssertEqual(try contextStore.core.currentSchemaVersion(), 2)
        XCTAssertEqual(
            try contextStore.core.message(chatID: ids.chatID, messageID: ids.messageID)?.body,
            "dia lagi di jalan"
        )

        let tables = try tableNames(at: url.path)
        XCTAssertTrue(tables.contains("translations"))
        XCTAssertTrue(tables.contains("vocabulary_entries"))
        XCTAssertTrue(tables.contains("known_words"))
        XCTAssertTrue(tables.contains("conversation_summaries"))
        XCTAssertTrue(tables.contains("persistence_component_versions"))
    }

    func testTranslationRevisionHistoryRoundTripsCacheAndManualEditMetadata() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteContextStore(path: url.path)
        let ids = try seedMessage(in: store.core)
        let firstTime = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 2_000))
        let secondTime = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 3_000))

        let first = try XCTUnwrap(StoredTranslation(
            chatID: ids.chatID,
            messageID: ids.messageID,
            sourceLanguage: "id",
            targetLanguage: "pl",
            revision: 1,
            revisionKind: .model,
            translatedBody: "Ona jest w drodze.",
            sourceHash: "source-v1",
            contextHash: "context-v1",
            promptVersion: "prompt-1",
            modelIdentifier: "local-model-1",
            knownWordsVersion: 4,
            contextMessageCount: 8,
            summaryVersion: 2,
            correctionComment: nil,
            createdAt: firstTime
        ))
        let manual = try XCTUnwrap(StoredTranslation(
            chatID: ids.chatID,
            messageID: ids.messageID,
            sourceLanguage: "id",
            targetLanguage: "pl",
            revision: 2,
            revisionKind: .manualEdit,
            translatedBody: "Cindy jest w drodze.",
            sourceHash: "source-v1",
            contextHash: "context-v2",
            promptVersion: "prompt-1",
            modelIdentifier: "local-model-1",
            knownWordsVersion: 5,
            contextMessageCount: 10,
            summaryVersion: 3,
            correctionComment: "dia means Cindy here",
            createdAt: secondTime
        ))

        try store.upsert(translation: first)
        try store.upsert(translation: manual)

        XCTAssertEqual(
            try store.translation(
                chatID: ids.chatID,
                messageID: ids.messageID,
                targetLanguage: "pl",
                revision: 1
            ),
            first
        )
        XCTAssertEqual(
            try store.latestTranslation(
                chatID: ids.chatID,
                messageID: ids.messageID,
                targetLanguage: "pl"
            ),
            manual
        )
        XCTAssertEqual(
            try store.translations(
                chatID: ids.chatID,
                messageID: ids.messageID,
                targetLanguage: "pl"
            ).map(\.revision),
            [2, 1]
        )

        try store.deleteTranslation(
            chatID: ids.chatID,
            messageID: ids.messageID,
            targetLanguage: "pl",
            revision: 2
        )
        XCTAssertEqual(
            try store.latestTranslation(
                chatID: ids.chatID,
                messageID: ids.messageID,
                targetLanguage: "pl"
            ),
            first
        )
    }

    func testVocabularyAndKnownWordsAreDeterministicAndVersioned() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteContextStore(path: url.path)
        let ids = try seedMessage(in: store.core)
        let timestamp = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 2_000))
        let translation = try XCTUnwrap(StoredTranslation(
            chatID: ids.chatID,
            messageID: ids.messageID,
            sourceLanguage: "id",
            targetLanguage: "pl",
            revision: 1,
            revisionKind: .model,
            translatedBody: "Ona jest w drodze.",
            sourceHash: "source",
            contextHash: "context",
            promptVersion: "prompt-1",
            modelIdentifier: "local-model-1",
            knownWordsVersion: 0,
            contextMessageCount: 3,
            summaryVersion: nil,
            correctionComment: nil,
            createdAt: timestamp
        ))
        try store.upsert(translation: translation)

        let mager = try XCTUnwrap(StoredVocabularyEntry(
            id: "entry-mager",
            chatID: ids.chatID,
            messageID: ids.messageID,
            sourceLanguage: "id",
            targetLanguage: "pl",
            translationRevision: 1,
            sourceText: "mager",
            normalizedSourceText: "mager",
            contextualMeaning: "nie chce mi się ruszać",
            literalMeaning: "malas gerak",
            unavailableReason: nil,
            contextHash: "context",
            createdAt: timestamp,
            updatedAt: timestamp
        ))
        let dia = try XCTUnwrap(StoredVocabularyEntry(
            id: "entry-dia",
            chatID: ids.chatID,
            messageID: ids.messageID,
            sourceLanguage: "id",
            targetLanguage: "pl",
            translationRevision: 1,
            sourceText: "dia",
            normalizedSourceText: "dia",
            contextualMeaning: nil,
            literalMeaning: nil,
            unavailableReason: "ambiguous without enough context",
            contextHash: "context",
            createdAt: timestamp,
            updatedAt: timestamp
        ))
        try store.upsert(vocabulary: mager)
        try store.upsert(vocabulary: dia)

        XCTAssertEqual(
            try store.vocabularyEntries(
                chatID: ids.chatID,
                messageID: ids.messageID,
                targetLanguage: "pl",
                translationRevision: 1
            ).map(\.normalizedSourceText),
            ["dia", "mager"]
        )

        XCTAssertEqual(try store.knownWordsVersion(), 0)
        let wkwk = try XCTUnwrap(StoredKnownWord(
            language: "id",
            normalizedText: "wkwk",
            displayText: "wkwk",
            createdAt: timestamp,
            updatedAt: timestamp
        ))
        let diaKnown = try XCTUnwrap(StoredKnownWord(
            language: "id",
            normalizedText: "dia",
            displayText: "dia",
            createdAt: timestamp,
            updatedAt: timestamp
        ))
        try store.upsert(knownWord: wkwk)
        try store.upsert(knownWord: diaKnown)

        XCTAssertEqual(try store.knownWordsVersion(), 2)
        XCTAssertEqual(try store.knownWords(language: "id").map(\.normalizedText), ["dia", "wkwk"])

        try store.deleteKnownWord(language: "id", normalizedText: "missing")
        XCTAssertEqual(try store.knownWordsVersion(), 2)
        try store.deleteKnownWord(language: "id", normalizedText: "dia")
        XCTAssertEqual(try store.knownWordsVersion(), 3)
        XCTAssertEqual(try store.knownWords(language: "id"), [wkwk])
    }

    func testConversationSummariesAreVersionedLinkedAndClearable() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteContextStore(path: url.path)
        let ids = try seedMessage(in: store.core)
        let through = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1_000))
        let firstTime = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 2_000))
        let secondTime = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 3_000))

        let first = try XCTUnwrap(StoredConversationSummary(
            chatID: ids.chatID,
            version: 1,
            throughMessageID: ids.messageID,
            throughTimestamp: through,
            sourceMessageCount: 10,
            contextHash: "summary-context-1",
            summaryText: "Rina is expected to join later.",
            promptVersion: "summary-1",
            modelIdentifier: "local-model-1",
            createdAt: firstTime
        ))
        let second = try XCTUnwrap(StoredConversationSummary(
            chatID: ids.chatID,
            version: 2,
            throughMessageID: ids.messageID,
            throughTimestamp: through,
            sourceMessageCount: 14,
            contextHash: "summary-context-2",
            summaryText: "Rina is joining later and Cindy is the referent for dia.",
            promptVersion: "summary-1",
            modelIdentifier: "local-model-1",
            createdAt: secondTime
        ))

        try store.upsert(summary: first)
        try store.upsert(summary: second)
        XCTAssertEqual(try store.latestSummary(chatID: ids.chatID), second)
        XCTAssertEqual(try store.summaries(chatID: ids.chatID).map(\.version), [2, 1])

        try store.deleteSummaries(chatID: ids.chatID)
        XCTAssertNil(try store.latestSummary(chatID: ids.chatID))
    }

    func testCorruptTranslationFailsExplicitlyAndFutureComponentVersionFailsClosed() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteContextStore(path: url.path)
        let ids = try seedMessage(in: store.core)
        let timestamp = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 2_000))
        let translation = try XCTUnwrap(StoredTranslation(
            chatID: ids.chatID,
            messageID: ids.messageID,
            sourceLanguage: "id",
            targetLanguage: "pl",
            revision: 1,
            revisionKind: .model,
            translatedBody: "x",
            sourceHash: "source",
            contextHash: "context",
            promptVersion: "prompt",
            modelIdentifier: "model",
            knownWordsVersion: 0,
            contextMessageCount: 0,
            summaryVersion: nil,
            correctionComment: nil,
            createdAt: timestamp
        ))
        try store.upsert(translation: translation)

        try executeRaw(
            url.path,
            sql: "PRAGMA ignore_check_constraints = ON; UPDATE translations SET revision_kind = 'bad';"
        )
        XCTAssertThrowsError(
            try store.translation(
                chatID: ids.chatID,
                messageID: ids.messageID,
                targetLanguage: "pl",
                revision: 1
            )
        ) { error in
            XCTAssertEqual(error as? SQLiteContextPersistenceError, .invalidStoredValue("translations"))
        }

        try executeRaw(
            url.path,
            sql: "UPDATE persistence_component_versions SET version = 99 WHERE component = 'translation_context';"
        )
        XCTAssertThrowsError(try SQLiteContextStore(path: url.path)) { error in
            XCTAssertEqual(error as? SQLiteContextPersistenceError, .unsupportedSchemaVersion(99))
        }
    }

    func testSchemaContainsNoAuthenticationOrSessionTables() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try SQLiteContextStore(path: url.path)

        let forbiddenFragments = ["cookie", "auth", "session", "pairing", "token", "credential"]
        for table in try tableNames(at: url.path) {
            let lower = table.lowercased()
            XCTAssertFalse(
                forbiddenFragments.contains(where: lower.contains),
                "unexpected sensitive table: \(table)"
            )
        }
    }

    private func seedCoreDatabase(at url: URL) throws -> (chatID: WhatsAppChatID, messageID: WhatsAppMessageID) {
        let core = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertEqual(try core.currentSchemaVersion(), 2)
        return try seedMessage(in: core)
    }

    private func seedMessage(
        in core: SQLiteWhatsAppStore
    ) throws -> (chatID: WhatsAppChatID, messageID: WhatsAppMessageID) {
        let chatID = try XCTUnwrap(WhatsAppChatID("group-1"))
        let messageID = try XCTUnwrap(WhatsAppMessageID("message-1"))
        try core.upsert(chat: try XCTUnwrap(WhatsAppChat(
            id: chatID,
            title: "Family",
            kind: .group,
            unreadCount: 0,
            lastMessageAt: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1_000))
        )))
        try core.upsert(message: WhatsAppMessage(
            id: messageID,
            chatID: chatID,
            senderID: nil,
            timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1_000)),
            body: "dia lagi di jalan",
            fromMe: false,
            quote: nil,
            media: nil,
            translation: nil
        ))
        return (chatID, messageID)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("whatsapp-context-persistence-\(UUID().uuidString).sqlite")
    }

    private func executeRaw(_ path: String, sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let db else { throw NSError(domain: "sqlite", code: 1) }
        defer { sqlite3_close(db) }
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw NSError(
                domain: "sqlite",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
            )
        }
    }

    private func tableNames(at path: String) throws -> [String] {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let db else { throw NSError(domain: "sqlite", code: 1) }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
        guard let statement else { throw NSError(domain: "sqlite", code: 2) }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) {
                names.append(String(cString: value))
            }
        }
        return names
    }
}
