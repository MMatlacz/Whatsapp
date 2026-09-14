import Foundation
import XCTest
import CSQLite
@testable import PersistenceCore
import WhatsAppDomainCore

final class PersistenceCoreTests: XCTestCase {
    func testFreshDatabaseMigratesAndRoundTripsDomainData() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertEqual(try store.currentSchemaVersion(), 5)

        let chatID = try XCTUnwrap(WhatsAppChatID("group-1"))
        let participantID = try XCTUnwrap(WhatsAppParticipantID("person-1"))
        let quoteSenderID = try XCTUnwrap(WhatsAppParticipantID("person-2"))
        let chat = try XCTUnwrap(WhatsAppChat(
            id: chatID,
            title: "Family",
            kind: .group,
            unreadCount: 2,
            lastMessageAt: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 2_000))
        ))
        let participant = WhatsAppParticipant(id: participantID, displayName: "P1")
        let quote = WhatsAppQuote(
            messageID: try XCTUnwrap(WhatsAppMessageID("quoted")),
            senderID: quoteSenderID,
            body: "Earlier"
        )
        let media = try XCTUnwrap(WhatsAppMediaMetadata(
            kind: .image,
            mimeType: "image/jpeg",
            filename: "photo.jpg",
            sizeBytes: 1_024,
            durationMilliseconds: nil,
            width: 800,
            height: 600
        ))
        let message = WhatsAppMessage(
            id: try XCTUnwrap(WhatsAppMessageID("m1")),
            chatID: chatID,
            senderID: participantID,
            timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1_500)),
            body: "halo",
            fromMe: false,
            quote: quote,
            media: media,
            translation: nil
        )

        try store.upsert(chat: chat)
        try store.upsert(participant: participant)
        try store.upsert(message: message)

        XCTAssertEqual(try store.chat(id: chatID), chat)
        XCTAssertEqual(try store.participant(id: participantID), participant)
        XCTAssertNil(try store.participant(id: quoteSenderID)?.displayName)
        XCTAssertEqual(try store.message(chatID: chatID, messageID: message.id), message)
    }

    func testMessageUpsertUpdatesWithoutDuplicationAndPreservesParticipantName() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteWhatsAppStore(path: url.path)
        let chatID = try XCTUnwrap(WhatsAppChatID("group-1"))
        let participantID = try XCTUnwrap(WhatsAppParticipantID("person-1"))
        try store.upsert(chat: try XCTUnwrap(WhatsAppChat(
            id: chatID,
            title: "Family",
            kind: .group,
            unreadCount: 0,
            lastMessageAt: nil
        )))
        try store.upsert(participant: WhatsAppParticipant(id: participantID, displayName: "Stable Name"))

        let messageID = try XCTUnwrap(WhatsAppMessageID("same-id"))
        try store.upsert(message: WhatsAppMessage(
            id: messageID,
            chatID: chatID,
            senderID: participantID,
            timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 100)),
            body: "first",
            fromMe: false,
            quote: nil,
            media: nil,
            translation: nil
        ))
        try store.upsert(message: WhatsAppMessage(
            id: messageID,
            chatID: chatID,
            senderID: participantID,
            timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 200)),
            body: "updated",
            fromMe: false,
            quote: nil,
            media: nil,
            translation: nil
        ))

        XCTAssertEqual(try store.messageCount(chatID: chatID), 1)
        XCTAssertEqual(try store.message(chatID: chatID, messageID: messageID)?.body, "updated")
        XCTAssertEqual(
            try store.message(chatID: chatID, messageID: messageID)?.timestamp.millisecondsSince1970,
            200
        )
        XCTAssertEqual(try store.participant(id: participantID)?.displayName, "Stable Name")
    }

    func testPaginationIsDeterministicForEqualTimestamps() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteWhatsAppStore(path: url.path)
        let chatID = try XCTUnwrap(WhatsAppChatID("group-1"))
        try store.upsert(chat: try XCTUnwrap(WhatsAppChat(
            id: chatID,
            title: "Family",
            kind: .group,
            unreadCount: 0,
            lastMessageAt: nil
        )))

        let timestamp = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1_000))
        for value in 1...5 {
            try store.upsert(message: WhatsAppMessage(
                id: try XCTUnwrap(WhatsAppMessageID("m\(value)")),
                chatID: chatID,
                senderID: nil,
                timestamp: timestamp,
                body: "message \(value)",
                fromMe: false,
                quote: nil,
                media: nil,
                translation: nil
            ))
        }

        let first = try store.messages(chatID: chatID, limit: 2)
        XCTAssertEqual(first.messages.map(\.id.rawValue), ["m5", "m4"])
        let second = try store.messages(chatID: chatID, before: first.nextCursor, limit: 2)
        XCTAssertEqual(second.messages.map(\.id.rawValue), ["m3", "m2"])
        let third = try store.messages(chatID: chatID, before: second.nextCursor, limit: 2)
        XCTAssertEqual(third.messages.map(\.id.rawValue), ["m1"])
        XCTAssertNil(third.nextCursor)
    }

    func testMessageRequiresExistingChatAndRejectsTranslationMetadata() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteWhatsAppStore(path: url.path)
        let chatID = try XCTUnwrap(WhatsAppChatID("missing"))
        let messageID = try XCTUnwrap(WhatsAppMessageID("m1"))
        let timestamp = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1))
        let message = WhatsAppMessage(
            id: messageID,
            chatID: chatID,
            senderID: nil,
            timestamp: timestamp,
            body: "x",
            fromMe: false,
            quote: nil,
            media: nil,
            translation: nil
        )

        XCTAssertThrowsError(try store.upsert(message: message)) { error in
            XCTAssertEqual(error as? SQLitePersistenceError, .missingChat(chatID))
        }

        try store.upsert(chat: try XCTUnwrap(WhatsAppChat(
            id: chatID,
            title: "Chat",
            kind: .direct,
            unreadCount: 0,
            lastMessageAt: nil
        )))
        let translation = try XCTUnwrap(WhatsAppTranslationMetadata(
            sourceLanguage: "id",
            targetLanguage: "pl",
            translatedBody: "x",
            contextMessageCount: 0,
            translatedAt: nil
        ))
        let translated = WhatsAppMessage(
            id: messageID,
            chatID: chatID,
            senderID: nil,
            timestamp: timestamp,
            body: "x",
            fromMe: false,
            quote: nil,
            media: nil,
            translation: translation
        )
        XCTAssertThrowsError(try store.upsert(message: translated)) { error in
            XCTAssertEqual(error as? SQLitePersistenceError, .unsupportedTranslationMetadata)
        }
    }

    func testCorruptStoredBooleanFailsExplicitly() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let chatID = try XCTUnwrap(WhatsAppChatID("group-1"))
        let messageID = try XCTUnwrap(WhatsAppMessageID("m1"))

        do {
            let store = try SQLiteWhatsAppStore(path: url.path)
            try store.upsert(chat: try XCTUnwrap(WhatsAppChat(
                id: chatID,
                title: "Family",
                kind: .group,
                unreadCount: 0,
                lastMessageAt: nil
            )))
            try store.upsert(message: WhatsAppMessage(
                id: messageID,
                chatID: chatID,
                senderID: nil,
                timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1)),
                body: "x",
                fromMe: false,
                quote: nil,
                media: nil,
                translation: nil
            ))
        }

        try executeRaw(
            url.path,
            sql: "PRAGMA ignore_check_constraints = ON; UPDATE messages SET from_me = 2;"
        )
        let reopened = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertThrowsError(try reopened.message(chatID: chatID, messageID: messageID)) { error in
            XCTAssertEqual(error as? SQLitePersistenceError, .invalidStoredValue("messages.from_me"))
        }
    }

    func testFutureSchemaVersionFailsClosed() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try executeRaw(url.path, sql: "PRAGMA user_version = 99;")

        XCTAssertThrowsError(try SQLiteWhatsAppStore(path: url.path)) { error in
            XCTAssertEqual(error as? SQLitePersistenceError, .unsupportedSchemaVersion(99))
        }
    }

    func testSemanticMessageContentRoundTripsAllCases() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteWhatsAppStore(path: url.path)
        let chatID = try XCTUnwrap(WhatsAppChatID("semantic-chat"))
        try store.upsert(chat: try XCTUnwrap(WhatsAppChat(
            id: chatID, title: "Semantic", kind: .direct, unreadCount: 0, lastMessageAt: nil
        )))

        let media = try XCTUnwrap(WhatsAppMediaMetadata(
            kind: .image, mimeType: "image/jpeg", filename: "photo.jpg",
            sizeBytes: 512, durationMilliseconds: nil, width: 320, height: 240
        ))
        let preview = try XCTUnwrap(WhatsAppLinkPreview(
            matchedText: "https://example.com", canonicalURL: "https://example.com/",
            title: "Example", description: "Preview"
        ))
        let cases: [(String, String?, WhatsAppMediaMetadata?, WhatsAppLinkPreview?, WhatsAppMessageContent)] = [
            ("text", "Halo", nil, nil, .text),
            ("media", "Caption", media, nil, .media),
            ("link", "https://example.com", nil, preview, .linkPreview),
            ("location", nil, nil, nil, .location(.init(
                latitude: 52.2297, longitude: 21.0122, name: "Warsaw", address: "Center"
            ))),
            ("contact", nil, nil, nil, .contact([
                .init(displayName: "A", vCard: "BEGIN:VCARD\nFN:A\nEND:VCARD")
            ])),
            ("poll", nil, nil, nil, .poll(.init(question: "Lunch?", options: ["Rice", "Soup"]))),
            ("revoked", nil, nil, nil, .revoked),
            ("system", nil, nil, nil, .system(.init(type: "group-notification", text: "A joined"))),
            ("unsupported", nil, nil, nil, .unsupported(rawType: "future-message-type")),
        ]

        for (index, item) in cases.enumerated() {
            let message = WhatsAppMessage(
                id: try XCTUnwrap(WhatsAppMessageID(item.0)),
                chatID: chatID,
                senderID: nil,
                timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: Int64(index + 1))),
                body: item.1,
                fromMe: false,
                quote: nil,
                media: item.2,
                linkPreview: item.3,
                content: item.4,
                translation: nil
            )
            try store.upsert(message: message)
            XCTAssertEqual(try store.message(chatID: chatID, messageID: message.id), message)
        }
    }

    func testVersionFourDatabaseMigratesSemanticColumnsWithoutLosingRows() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try createVersionFourDatabase(url.path)

        let store = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertEqual(try store.currentSchemaVersion(), 5)
        let chatID = try XCTUnwrap(WhatsAppChatID("legacy-chat"))
        XCTAssertEqual(try store.messageCount(chatID: chatID), 3)

        let text = try XCTUnwrap(store.message(
            chatID: chatID, messageID: try XCTUnwrap(WhatsAppMessageID("legacy-text"))
        ))
        XCTAssertEqual(text.body, "legacy text")
        XCTAssertEqual(text.content, .text)

        let media = try XCTUnwrap(store.message(
            chatID: chatID, messageID: try XCTUnwrap(WhatsAppMessageID("legacy-media"))
        ))
        XCTAssertEqual(media.media?.kind, .image)
        XCTAssertEqual(media.media?.isViewOnce, true)
        XCTAssertEqual(media.deliveryState, .read)
        XCTAssertEqual(media.content, .media)

        let preview = try XCTUnwrap(store.message(
            chatID: chatID, messageID: try XCTUnwrap(WhatsAppMessageID("legacy-link"))
        ))
        XCTAssertEqual(preview.linkPreview?.title, "Legacy preview")
        XCTAssertEqual(preview.content, .linkPreview)
    }

    func testCorruptSemanticContentMetadataFailsExplicitly() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let chatID = try XCTUnwrap(WhatsAppChatID("chat"))
        let messageID = try XCTUnwrap(WhatsAppMessageID("system"))

        do {
            let store = try SQLiteWhatsAppStore(path: url.path)
            try store.upsert(chat: try XCTUnwrap(WhatsAppChat(
                id: chatID, title: "Chat", kind: .direct, unreadCount: 0, lastMessageAt: nil
            )))
            try store.upsert(message: WhatsAppMessage(
                id: messageID,
                chatID: chatID,
                senderID: nil,
                timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1)),
                body: nil,
                fromMe: false,
                quote: nil,
                media: nil,
                content: .system(.init(type: "notification", text: "Joined")),
                translation: nil
            ))
        }

        try executeRaw(url.path, sql: """
            UPDATE messages
            SET content_kind = 'contact', content_json = '{"version":1,"contacts":[]}'
            WHERE whatsapp_message_id = 'system';
            """)
        let reopened = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertThrowsError(try reopened.message(chatID: chatID, messageID: messageID)) { error in
            XCTAssertEqual(error as? SQLitePersistenceError, .invalidStoredValue("messages.content"))
        }
    }

    func testSemanticMigrationRollsBackOnInjectedSchemaFailure() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try createVersionFourDatabase(url.path)
        try executeRaw(url.path, sql: "ALTER TABLE messages ADD COLUMN content_json TEXT NULL;")

        XCTAssertThrowsError(try SQLiteWhatsAppStore(path: url.path))
        XCTAssertEqual(try rawUserVersion(url.path), 4)
        let columns = try tableColumns(url.path, table: "messages")
        XCTAssertFalse(columns.contains("content_kind"), "first ALTER must roll back with the failed migration")
        XCTAssertTrue(columns.contains("content_json"), "pre-existing injected column must remain")
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("whatsapp-persistence-\(UUID().uuidString).sqlite")
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

    private func createVersionFourDatabase(_ path: String) throws {
        try executeRaw(path, sql: """
            CREATE TABLE chats(
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                kind TEXT NOT NULL,
                unread_count INTEGER NOT NULL,
                last_message_at_ms INTEGER NULL
            );
            CREATE TABLE messages(
                chat_id TEXT NOT NULL,
                whatsapp_message_id TEXT NOT NULL,
                sender_id TEXT NULL,
                timestamp_ms INTEGER NOT NULL,
                body TEXT NULL,
                from_me INTEGER NOT NULL,
                quote_message_id TEXT NULL,
                quote_sender_id TEXT NULL,
                quote_body TEXT NULL,
                media_kind TEXT NULL,
                media_mime_type TEXT NULL,
                media_filename TEXT NULL,
                media_size_bytes INTEGER NULL,
                media_duration_ms INTEGER NULL,
                media_width INTEGER NULL,
                media_height INTEGER NULL,
                delivery_state TEXT NULL,
                media_is_view_once INTEGER NOT NULL DEFAULT 0,
                link_preview_matched_text TEXT NULL,
                link_preview_canonical_url TEXT NULL,
                link_preview_title TEXT NULL,
                link_preview_description TEXT NULL,
                PRIMARY KEY(chat_id, whatsapp_message_id)
            );
            CREATE INDEX messages_by_chat_time
                ON messages(chat_id, timestamp_ms DESC, whatsapp_message_id DESC);
            INSERT INTO chats(id, title, kind, unread_count, last_message_at_ms)
                VALUES ('legacy-chat', 'Legacy', 'direct', 0, 3000);
            INSERT INTO messages(
                chat_id, whatsapp_message_id, timestamp_ms, body, from_me, media_is_view_once
            ) VALUES ('legacy-chat', 'legacy-text', 1000, 'legacy text', 0, 0);
            INSERT INTO messages(
                chat_id, whatsapp_message_id, timestamp_ms, body, from_me,
                media_kind, media_mime_type, media_size_bytes, media_width, media_height,
                delivery_state, media_is_view_once
            ) VALUES (
                'legacy-chat', 'legacy-media', 2000, NULL, 0,
                'image', 'image/jpeg', 1024, 640, 480, 'read', 1
            );
            INSERT INTO messages(
                chat_id, whatsapp_message_id, timestamp_ms, body, from_me, media_is_view_once,
                link_preview_matched_text, link_preview_canonical_url,
                link_preview_title, link_preview_description
            ) VALUES (
                'legacy-chat', 'legacy-link', 3000, 'https://example.com', 0, 0,
                'https://example.com', 'https://example.com/', 'Legacy preview', 'Description'
            );
            PRAGMA user_version = 4;
            """)
    }

    private func rawUserVersion(_ path: String) throws -> Int32 {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "sqlite", code: 1)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw NSError(domain: "sqlite", code: 2) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw NSError(domain: "sqlite", code: 3) }
        return sqlite3_column_int(statement, 0)
    }

    private func tableColumns(_ path: String, table: String) throws -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "sqlite", code: 1)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw NSError(domain: "sqlite", code: 2) }
        defer { sqlite3_finalize(statement) }
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: raw))
            }
        }
        return columns
    }
}
