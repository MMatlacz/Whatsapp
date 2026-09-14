import XCTest
@testable import WhatsAppBridgeCore

@MainActor
final class WhatsAppBridgePendingRequestTests: XCTestCase {
    func testRequestSpecificTimeoutPolicy() {
        XCTAssertEqual(WhatsAppBridgeRequestTimeouts.timeout(for: .connectionState), .seconds(15))
        XCTAssertEqual(WhatsAppBridgeRequestTimeouts.timeout(for: .loadMessages), .seconds(15))
        XCTAssertEqual(WhatsAppBridgeRequestTimeouts.timeout(for: .sendText), .seconds(15))
        XCTAssertEqual(WhatsAppBridgeRequestTimeouts.timeout(for: .mediaPreview), .seconds(30))
    }

    func testSuccessCancelsTimeoutAndLateCompletionIsIgnored() async throws {
        let store = WhatsAppBridgePendingRequestStore()
        let expected = Data("ok".utf8)
        let task = Task { @MainActor in
            try await store.awaitResponse(requestID: "success", timeout: .milliseconds(50)) {}
        }

        await waitUntilPending(store, count: 1)
        XCTAssertTrue(store.complete("success", data: expected))
        let result = try await task.value
        XCTAssertEqual(result, expected)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertFalse(store.complete("success", data: Data("late".utf8)))

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.pendingCount, 0)
    }

    func testTimeoutResumesExactlyOnceAndRemovesPendingState() async {
        let store = WhatsAppBridgePendingRequestStore()
        do {
            _ = try await store.awaitResponse(requestID: "timeout", timeout: .milliseconds(20)) {}
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? WhatsAppWebTransportError, .requestTimedOut("timeout"))
        }
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertFalse(store.fail("timeout", error: WhatsAppWebTransportError.bridgeUnavailable("late")))
    }

    func testCallerCancellationRemovesPendingStateAndLateResponseIsIgnored() async {
        let store = WhatsAppBridgePendingRequestStore()
        let task = Task { @MainActor in
            try await store.awaitResponse(requestID: "cancel", timeout: .seconds(5)) {}
        }

        await waitUntilPending(store, count: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertFalse(store.complete("cancel", data: Data("late".utf8)))
    }

    func testDisconnectFailsAllPendingAndCancelsTheirTimeouts() async {
        let store = WhatsAppBridgePendingRequestStore()
        let first = Task { @MainActor in
            try await store.awaitResponse(requestID: "a", timeout: .seconds(5)) {}
        }
        let second = Task { @MainActor in
            try await store.awaitResponse(requestID: "b", timeout: .seconds(5)) {}
        }

        await waitUntilPending(store, count: 2)
        let disconnect = WhatsAppWebTransportError.bridgeUnavailable("disconnect")
        store.failAll(with: disconnect)

        for task in [first, second] {
            do {
                _ = try await task.value
                XCTFail("Expected disconnect failure")
            } catch {
                XCTAssertEqual(error as? WhatsAppWebTransportError, disconnect)
            }
        }
        XCTAssertEqual(store.pendingCount, 0)
    }

    func testNewRequestWithSameIDSupersedesOldPendingOwnerSafely() async throws {
        let store = WhatsAppBridgePendingRequestStore()
        let old = Task { @MainActor in
            try await store.awaitResponse(requestID: "same", timeout: .seconds(5)) {}
        }
        await waitUntilPending(store, count: 1)

        let newer = Task { @MainActor in
            try await store.awaitResponse(requestID: "same", timeout: .seconds(5)) {}
        }
        do {
            _ = try await old.value
            XCTFail("Expected duplicate request failure")
        } catch {
            XCTAssertEqual(
                error as? WhatsAppWebTransportError,
                .bridgeUnavailable("duplicate-request-id")
            )
        }
        await waitUntilPending(store, count: 1)
        XCTAssertTrue(store.complete("same", data: Data("new".utf8)))
        let result = try await newer.value
        XCTAssertEqual(result, Data("new".utf8))
    }

    private func waitUntilPending(
        _ store: WhatsAppBridgePendingRequestStore,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 where store.pendingCount != count {
            await Task.yield()
        }
        XCTAssertEqual(store.pendingCount, count, file: file, line: line)
    }
}
