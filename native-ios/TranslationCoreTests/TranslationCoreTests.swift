import XCTest
import WhatsAppDomainCore
@testable import TranslationCore

final class TranslationCoreTests: XCTestCase {
    func testRecentContextReturnsRequestedSuffix() {
        let messages = ["one", "two", "three", "four"]

        XCTAssertEqual(
            BoundedContext.recent(messages, limit: 2),
            ["three", "four"]
        )
    }

    func testRecentContextReturnsAllMessagesWhenLimitExceedsCount() {
        let messages = ["one", "two"]

        XCTAssertEqual(
            BoundedContext.recent(messages, limit: 10),
            messages
        )
    }

    func testRecentContextTreatsNonPositiveLimitAsEmpty() {
        let messages = ["one", "two"]

        XCTAssertTrue(BoundedContext.recent(messages, limit: 0).isEmpty)
        XCTAssertTrue(BoundedContext.recent(messages, limit: -1).isEmpty)
    }

    func testContextBuilderUsesEightRecentTurnsByDefault() throws {
        let history = try (1...10).map { index in
            try makeMessage(
                id: "m\(String(format: "%02d", index))",
                sender: index.isMultiple(of: 2) ? "sari" : "rina",
                timestamp: Int64(index),
                body: "turn \(index)"
            )
        }
        let target = try makeMessage(
            id: "target",
            sender: "sari",
            timestamp: 20,
            body: "Dia sudah bilang belum?"
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: history
        )

        XCTAssertEqual(context.recentTurns.count, 8)
        XCTAssertEqual(context.recentTurns.first?.body, "turn 3")
        XCTAssertEqual(context.recentTurns.last?.body, "turn 10")
    }

    func testContextBuilderRejectsMoreThanSixteenRecentTurns() throws {
        let target = try makeMessage(
            id: "target",
            sender: "sari",
            timestamp: 20,
            body: "Nanti aja."
        )

        XCTAssertThrowsError(
            try TranslationContextBuilder().build(
                target: target,
                conversation: [],
                recentTurnLimit: 17
            )
        ) { error in
            XCTAssertEqual(
                error as? TranslationContextBuilderError,
                .invalidRecentTurnLimit(17)
            )
        }
    }

    func testContextBuilderPreservesSpeakerIdentityForOmittedSubjectCase() throws {
        let history = [
            try makeMessage(id: "m1", sender: "rina", timestamp: 1, body: "Aku masih di kantor."),
            try makeMessage(id: "m2", sender: "sari", timestamp: 2, body: "Rina bilang bakal nyusul."),
            try makeMessage(id: "m3", sender: "bapak", timestamp: 3, body: "Kalau telat, pesan duluan."),
        ]
        let target = try makeMessage(
            id: "target",
            sender: "sari",
            timestamp: 4,
            body: "Sudah bilang belum?"
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: history
        )

        XCTAssertEqual(context.recentTurns.map(\.body), [
            "Aku masih di kantor.",
            "Rina bilang bakal nyusul.",
            "Kalau telat, pesan duluan.",
        ])
        XCTAssertEqual(context.recentTurns.map(\.speaker.rawValue), ["P2", "P3", "P1"])
        XCTAssertEqual(context.target.speaker.rawValue, "P3")
    }

    func testAliasesAndOrderingAreDeterministicForSameConversation() throws {
        let first = try makeMessage(id: "b", sender: "zeta", timestamp: 10, body: "second")
        let second = try makeMessage(id: "a", sender: "alpha", timestamp: 10, body: "first")
        let target = try makeMessage(id: "z", sender: "zeta", timestamp: 11, body: "target")
        let builder = TranslationContextBuilder()

        let contextA = try builder.build(
            target: target,
            conversation: [first, second]
        )
        let contextB = try builder.build(
            target: target,
            conversation: [second, first]
        )

        XCTAssertEqual(contextA, contextB)
        XCTAssertEqual(contextA.recentTurns.map(\.body), ["first", "second"])
        XCTAssertEqual(contextA.recentTurns.map(\.speaker.rawValue), ["P1", "P2"])
        XCTAssertEqual(contextA.target.speaker.rawValue, "P2")
    }

    func testTargetQuoteOutsideRecentWindowIsIncludedWithoutDuplication() throws {
        let quoted = try makeMessage(
            id: "m01",
            sender: "rina",
            timestamp: 1,
            body: "Aku ikut, tapi nanti nyusul."
        )
        var history = [quoted]
        for index in 2...10 {
            history.append(
                try makeMessage(
                    id: "m\(String(format: "%02d", index))",
                    sender: "sari",
                    timestamp: Int64(index),
                    body: "later \(index)"
                )
            )
        }
        let target = try makeMessage(
            id: "target",
            sender: "sari",
            timestamp: 20,
            body: "Dia bilang begitu kok.",
            quote: try makeQuote(
                messageID: "m01",
                sender: "rina",
                body: "stale fallback body"
            )
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: history,
            recentTurnLimit: 8
        )

        XCTAssertEqual(
            context.quotedTurn,
            TranslationQuotedTurn(
                speaker: try XCTUnwrap(TranslationSpeakerAlias(rawValue: "P1")),
                body: "Aku ikut, tapi nanti nyusul."
            )
        )
        XCTAssertEqual(context.recentTurns.count, 8)
        XCTAssertFalse(context.recentTurns.contains { $0.body == "Aku ikut, tapi nanti nyusul." })
        XCTAssertEqual(context.recentTurns.first?.body, "later 3")
    }

    func testTargetQuoteInsideRecentWindowIsNotDuplicated() throws {
        let history = [
            try makeMessage(id: "m1", sender: "rina", timestamp: 1, body: "older"),
            try makeMessage(id: "m2", sender: "sari", timestamp: 2, body: "quoted body"),
            try makeMessage(id: "m3", sender: "rina", timestamp: 3, body: "newer"),
        ]
        let target = try makeMessage(
            id: "target",
            sender: "rina",
            timestamp: 4,
            body: "Maksudnya ini.",
            quote: try makeQuote(messageID: "m2", sender: "sari", body: nil)
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: history,
            recentTurnLimit: 3
        )

        XCTAssertEqual(context.quotedTurn?.body, "quoted body")
        XCTAssertEqual(context.recentTurns.map(\.body), ["older", "newer"])
        XCTAssertFalse(context.recentTurns.contains { $0.body == "quoted body" })
    }

    func testInlineQuoteFallbackWorksWhenReferencedMessageIsUnavailable() throws {
        let target = try makeMessage(
            id: "target",
            sender: "sari",
            timestamp: 5,
            body: "Iya, yang itu.",
            quote: try makeQuote(
                messageID: "missing",
                sender: "rina",
                body: "Aku nanti nyusul."
            )
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: []
        )

        XCTAssertEqual(context.quotedTurn?.body, "Aku nanti nyusul.")
        XCTAssertEqual(context.quotedTurn?.speaker.rawValue, "P1")
    }

    func testFromMeWithoutSenderIDUsesLocalAliasAndUnknownIncomingUsesUnknownAlias() throws {
        let history = [
            try makeMessage(
                id: "m1",
                sender: nil,
                timestamp: 1,
                body: "my message",
                fromMe: true
            ),
            try makeMessage(
                id: "m2",
                sender: nil,
                timestamp: 2,
                body: "unknown incoming"
            ),
        ]
        let target = try makeMessage(
            id: "target",
            sender: nil,
            timestamp: 3,
            body: "my target",
            fromMe: true
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: history
        )

        XCTAssertEqual(context.recentTurns.map(\.speaker), [.localUser, .unknown])
        XCTAssertEqual(context.target.speaker, .localUser)
    }

    func testContextIgnoresOtherChatsAndFutureMessages() throws {
        let history = [
            try makeMessage(id: "m1", sender: "rina", timestamp: 1, body: "include"),
            try makeMessage(
                id: "m2",
                chat: "other-chat",
                sender: "sari",
                timestamp: 2,
                body: "other chat"
            ),
            try makeMessage(id: "m3", sender: "sari", timestamp: 30, body: "future"),
        ]
        let target = try makeMessage(
            id: "target",
            sender: "rina",
            timestamp: 20,
            body: "target"
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: history
        )

        XCTAssertEqual(context.recentTurns.map(\.body), ["include"])
    }

    func testSummaryIsPassedThroughWithoutPersistenceCoupling() throws {
        let summary = try XCTUnwrap(
            TranslationContextSummary(
                version: 2,
                body: "P1 plans to join later; P2 already informed the family.",
                sourceMessageCount: 24
            )
        )
        let target = try makeMessage(
            id: "target",
            sender: "sari",
            timestamp: 20,
            body: "Dia jadi ikut kan?"
        )

        let context = try TranslationContextBuilder().build(
            target: target,
            conversation: [],
            summary: summary
        )

        XCTAssertEqual(context.summary, summary)
    }

    func testTargetWithoutTextIsRejected() throws {
        let target = try makeMessage(
            id: "target",
            sender: "sari",
            timestamp: 20,
            body: "   "
        )

        XCTAssertThrowsError(
            try TranslationContextBuilder().build(
                target: target,
                conversation: []
            )
        ) { error in
            XCTAssertEqual(error as? TranslationContextBuilderError, .targetHasNoText)
        }
    }

    func testBenchmarkMatrixContainsExpectedContextWindows() {
        let contextual = P01BenchmarkFixtures.requests.filter {
            $0.route == "Contextual Indonesian -> Polish"
        }

        XCTAssertEqual(contextual.map(\.contextWindow), [0, 3, 8, 16])
    }

    func testZeroContextPromptContainsNoPriorContext() throws {
        let request = try XCTUnwrap(
            P01BenchmarkFixtures.requests.first {
                $0.contextWindow == 0 && $0.id.hasPrefix("contextual-")
            }
        )

        XCTAssertTrue(request.prompt.contains("No prior context."))
        XCTAssertFalse(request.prompt.contains("Rina: Nanti aku nyusul."))
    }

    func testThreeMessageContextUsesOnlyMostRecentMessages() throws {
        let request = try XCTUnwrap(
            P01BenchmarkFixtures.requests.first { $0.contextWindow == 3 }
        )

        XCTAssertTrue(request.prompt.contains("Sari: Marcin agak panik karena jadwal berubah."))
        XCTAssertTrue(request.prompt.contains("Tante: Santai saja, aku tunggu di rumah."))
        XCTAssertTrue(request.prompt.contains("Rina: Nanti aku nyusul."))
        XCTAssertFalse(request.prompt.contains("Bapak: Jangan lupa bawa martabak."))
    }

    func testFullContextIncludesOldestAndNewestMessages() throws {
        let request = try XCTUnwrap(
            P01BenchmarkFixtures.requests.first { $0.contextWindow == 16 }
        )

        XCTAssertTrue(request.prompt.contains("Marcin: Czy Rina jedzie z nami do cioci?"))
        XCTAssertTrue(request.prompt.contains("Rina: Nanti aku nyusul."))
    }

    private func makeMessage(
        id: String,
        chat: String = "chat",
        sender: String?,
        timestamp: Int64,
        body: String?,
        fromMe: Bool = false,
        quote: WhatsAppQuote? = nil
    ) throws -> WhatsAppMessage {
        WhatsAppMessage(
            id: try XCTUnwrap(WhatsAppMessageID(id)),
            chatID: try XCTUnwrap(WhatsAppChatID(chat)),
            senderID: try sender.map { try XCTUnwrap(WhatsAppParticipantID($0)) },
            timestamp: try XCTUnwrap(
                WhatsAppTimestamp(millisecondsSince1970: timestamp)
            ),
            body: body,
            fromMe: fromMe,
            quote: quote,
            media: nil,
            translation: nil
        )
    }

    private func makeQuote(
        messageID: String,
        sender: String?,
        body: String?
    ) throws -> WhatsAppQuote {
        WhatsAppQuote(
            messageID: try XCTUnwrap(WhatsAppMessageID(messageID)),
            senderID: try sender.map { try XCTUnwrap(WhatsAppParticipantID($0)) },
            body: body
        )
    }
}
