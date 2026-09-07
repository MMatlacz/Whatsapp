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
        XCTAssertEqual(try store.currentSchemaVersion(), 1)

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
}
