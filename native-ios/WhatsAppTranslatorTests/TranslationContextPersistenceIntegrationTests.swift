import Foundation
import XCTest
@testable import WhatsAppBridgeCore
import PersistenceCore
import TranslationCore
import WhatsAppDomainCore

final class TranslationContextPersistenceIntegrationTests: XCTestCase {
    func testPersistedConversationMatchesEquivalentInMemoryContext() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteContextStore(path: url.path)
        let fixture = try makeFixture(store: store)

        let source = SQLiteTranslationContextSource(store: store)
        let persisted = try await TranslationContextAssembler(source: source).assemble(
            chatID: fixture.chatID,
            messageID: fixture.target.id,
            recentTurnLimit: 3
        )

        let expectedSummary = try XCTUnwrap(TranslationContextSummary(
            version: 2,
            body: "Older family context",
            sourceMessageCount: 2
        ))
        let expected = try TranslationContextBuilder().build(
            target: fixture.target,
            conversation: [fixture.messages[3], fixture.messages[5], fixture.messages[6], fixture.messages[0]],
            summary: expectedSummary,
            recentTurnLimit: 3
        )

        XCTAssertEqual(persisted, expected)
        XCTAssertEqual(persisted.quotedTurn?.body, "quoted outside recent window")
        XCTAssertEqual(persisted.recentTurns.map(\.body), ["recent three", "recent two", "recent one"])
        XCTAssertTrue(
            ([persisted.target.speaker] + persisted.recentTurns.map(\.speaker) + [persisted.quotedTurn?.speaker].compactMap { $0 })
                .allSatisfy { $0.rawValue == "SELF" || $0.rawValue == "UNKNOWN" || $0.rawValue.hasPrefix("P") }
        )
    }

    func testAssemblyWorksAfterStoreReopenWithoutLiveTransport() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let key: (WhatsAppChatID, WhatsAppMessageID)
        do {
            let store = try SQLiteContextStore(path: url.path)
            let fixture = try makeFixture(store: store)
            key = (fixture.chatID, fixture.target.id)
        }

        let reopened = try SQLiteContextStore(path: url.path)
        let context = try await TranslationContextAssembler(
            source: SQLiteTranslationContextSource(store: reopened)
        ).assemble(chatID: key.0, messageID: key.1, recentTurnLimit: 3)

        XCTAssertEqual(context.target.body, "target text")
        XCTAssertEqual(context.quotedTurn?.body, "quoted outside recent window")
        XCTAssertEqual(context.summary?.body, "Older family context")
    }

    func testSummaryBeyondTargetBoundaryIsIgnored() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteContextStore(path: url.path)
        let fixture = try makeFixture(store: store)
        let future = try message(
            id: "m09", chatID: fixture.chatID, sender: "sender-a", timestamp: 9_000,
            body: "future", fromMe: false
        )
        try store.core.upsert(message: future)
        let futureSummary = try XCTUnwrap(StoredConversationSummary(
            chatID: fixture.chatID,
            version: 3,
            throughMessageID: future.id,
            throughTimestamp: future.timestamp,
            sourceMessageCount: 9,
            contextHash: "future-hash",
            summaryText: "must not be visible to target",
            promptVersion: "summary-v1",
            modelIdentifier: "fixture-model",
            createdAt: future.timestamp
        ))
        try store.upsert(summary: futureSummary)

        let context = try await TranslationContextAssembler(
            source: SQLiteTranslationContextSource(store: store)
        ).assemble(chatID: fixture.chatID, messageID: fixture.target.id, recentTurnLimit: 3)

        XCTAssertNil(context.summary)
    }

    func testMissingTargetFailsExplicitly() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteContextStore(path: url.path)
        let chatID = try XCTUnwrap(WhatsAppChatID("missing-chat"))
        let messageID = try XCTUnwrap(WhatsAppMessageID("missing-message"))

        do {
            _ = try await TranslationContextAssembler(
                source: SQLiteTranslationContextSource(store: store)
            ).assemble(chatID: chatID, messageID: messageID)
            XCTFail("Expected missing target failure")
        } catch {
            XCTAssertEqual(
                error as? TranslationContextAssemblyError,
                .missingTarget(chatID: chatID, messageID: messageID)
            )
        }
    }

    private struct Fixture {
        let chatID: WhatsAppChatID
        let messages: [WhatsAppMessage]
        let target: WhatsAppMessage
    }

    private func makeFixture(store: SQLiteContextStore) throws -> Fixture {
        let chatID = try XCTUnwrap(WhatsAppChatID("family@g.us"))
        let senderA = try XCTUnwrap(WhatsAppParticipantID("participant-a"))
        let targetID = try XCTUnwrap(WhatsAppMessageID("m08"))
        let targetTimestamp = try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 8_000))
        let chat = try XCTUnwrap(WhatsAppChat(
            id: chatID,
            title: "Private display name not used by context",
            kind: .group,
            unreadCount: 0,
            lastMessageAt: targetTimestamp
        ))
        try store.core.upsert(chat: chat)

        let specs: [(String, String, Int64, String?)] = [
            ("m01", "participant-a", 1_000, "quoted outside recent window"),
            ("m02", "participant-b", 2_000, "old summary boundary"),
            ("m03", "participant-c", 3_000, "older text"),
            ("m04", "participant-c", 4_000, "recent three"),
            ("m05", "participant-b", 5_000, nil),
            ("m06", "participant-b", 6_000, "recent two"),
            ("m07", "participant-c", 7_000, "recent one"),
        ]
        let messages = try specs.map { try message(
            id: $0.0, chatID: chatID, sender: $0.1, timestamp: $0.2, body: $0.3, fromMe: false
        ) }
        for value in messages { try store.core.upsert(message: value) }

        let target = WhatsAppMessage(
            id: targetID,
            chatID: chatID,
            senderID: try XCTUnwrap(WhatsAppParticipantID("participant-b")),
            timestamp: targetTimestamp,
            body: "target text",
            fromMe: false,
            quote: WhatsAppQuote(messageID: messages[0].id, senderID: senderA, body: nil),
            media: nil,
            translation: nil
        )
        try store.core.upsert(message: target)

        let summary = try XCTUnwrap(StoredConversationSummary(
            chatID: chatID,
            version: 2,
            throughMessageID: messages[1].id,
            throughTimestamp: messages[1].timestamp,
            sourceMessageCount: 2,
            contextHash: "context-hash",
            summaryText: "Older family context",
            promptVersion: "summary-v1",
            modelIdentifier: "fixture-model",
            createdAt: messages[1].timestamp
        ))
        try store.upsert(summary: summary)

        return Fixture(chatID: chatID, messages: messages, target: target)
    }

    private func message(
        id: String,
        chatID: WhatsAppChatID,
        sender: String,
        timestamp: Int64,
        body: String?,
        fromMe: Bool
    ) throws -> WhatsAppMessage {
        WhatsAppMessage(
            id: try XCTUnwrap(WhatsAppMessageID(id)),
            chatID: chatID,
            senderID: try XCTUnwrap(WhatsAppParticipantID(sender)),
            timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: timestamp)),
            body: body,
            fromMe: fromMe,
            quote: nil,
            media: nil,
            translation: nil
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("translation-context-\(UUID().uuidString).sqlite")
    }
}
