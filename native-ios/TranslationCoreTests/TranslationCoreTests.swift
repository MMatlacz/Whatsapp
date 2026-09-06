import XCTest
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
}
