import Foundation
import XCTest
import CSQLite
import PersistenceCore
import WhatsAppDomainCore

final class DraftPersistenceTests: XCTestCase {
    func testDraftsSurviveReopenAndClearingWithoutCachedChats() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let chatID = try XCTUnwrap(WhatsAppChatID("test@c.us"))
        do {
            let store = try SQLiteWhatsAppStore(path: url.path)
            try store.saveDraft("  Cześć 👋\nunfinished", chatID: chatID)
        }
        do {
            let store = try SQLiteWhatsAppStore(path: url.path)
            XCTAssertEqual(try store.drafts()[chatID.rawValue], "  Cześć 👋\nunfinished")
            try store.saveDraft("", chatID: chatID)
        }
        let reopened = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertEqual(try reopened.drafts()[chatID.rawValue], "")
    }

    func testVersionOneDatabaseMigratesToDraftStorage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version = 1", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let store = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertEqual(try store.currentSchemaVersion(), 3)
        let chatID = try XCTUnwrap(WhatsAppChatID("offline@c.us"))
        try store.saveDraft("kept", chatID: chatID)
        XCTAssertEqual(try store.drafts(), [chatID.rawValue: "kept"])
    }

    func testReplyTargetAndPendingSendSurviveReopenAndCanBeCleared() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let chatID = try XCTUnwrap(WhatsAppChatID("test@c.us"))
        let pending = StoredPendingSend(
            chatID: chatID.rawValue, body: "possibly sent", quoteMessageID: "quoted",
            knownMessageIDs: ["old-1", "old-2"], attemptStartedMilliseconds: 12_345,
            historyChecked: false
        )
        do {
            let store = try SQLiteWhatsAppStore(path: url.path)
            try store.saveReplyTarget("quoted", chatID: chatID)
            try store.savePendingSend(pending)
        }
        do {
            let store = try SQLiteWhatsAppStore(path: url.path)
            XCTAssertEqual(try store.replyTargets(), [chatID.rawValue: "quoted"])
            XCTAssertEqual(try store.pendingSends(), [pending])
            try store.saveReplyTarget(nil, chatID: chatID)
            try store.deletePendingSend(chatID: chatID)
        }
        let reopened = try SQLiteWhatsAppStore(path: url.path)
        XCTAssertTrue(try reopened.replyTargets().isEmpty)
        XCTAssertTrue(try reopened.pendingSends().isEmpty)
    }
}
