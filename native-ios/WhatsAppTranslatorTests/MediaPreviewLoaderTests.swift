import XCTest
@testable import WhatsAppBridgeCore

final class MediaPreviewLoaderTests: XCTestCase {
    func testTwentyDuplicateRequestsCoalesceIntoOneFetch() async {
        let probe = MediaFetchProbe(delay: .milliseconds(30))
        let loader = MediaPreviewLoader { key in try await probe.fetch(key) }
        let key = makeKey(messageID: "same")

        let states = await withTaskGroup(of: MediaPreviewState.self, returning: [MediaPreviewState].self) { group in
            for _ in 0..<20 {
                group.addTask { await loader.load(key, isViewOnce: false) }
            }
            var values: [MediaPreviewState] = []
            for await value in group { values.append(value) }
            return values
        }

        let duplicateCalls = await probe.callCount(for: key)
        XCTAssertEqual(duplicateCalls, 1)
        XCTAssertEqual(states.count, 20)
        XCTAssertTrue(states.allSatisfy { if case .ready = $0 { return true }; return false })
    }

    func testConcurrencyNeverExceedsConfiguredLimit() async {
        let probe = MediaFetchProbe(delay: .milliseconds(35))
        let loader = MediaPreviewLoader(maximumConcurrentRequests: 2) { key in
            try await probe.fetch(key)
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                let key = makeKey(messageID: "m\(index)")
                group.addTask { _ = await loader.load(key, isViewOnce: false) }
            }
        }

        let totalCalls = await probe.totalCalls
        let maximumConcurrent = await probe.maximumConcurrent
        XCTAssertEqual(totalCalls, 10)
        XCTAssertLessThanOrEqual(maximumConcurrent, 2)
    }

    func testAttachmentAndLinkPreviewKeysNeverAlias() async {
        let probe = MediaFetchProbe()
        let loader = MediaPreviewLoader { key in try await probe.fetch(key) }
        let attachment = makeKey(messageID: "m1", purpose: .attachment, size: 320)
        let link = makeKey(messageID: "m1", purpose: .linkPreview, size: 320)

        async let first = loader.load(attachment, isViewOnce: false)
        async let second = loader.load(link, isViewOnce: false)
        _ = await (first, second)

        let attachmentCalls = await probe.callCount(for: attachment)
        let linkCalls = await probe.callCount(for: link)
        let totalCalls = await probe.totalCalls
        XCTAssertEqual(attachmentCalls, 1)
        XCTAssertEqual(linkCalls, 1)
        XCTAssertEqual(totalCalls, 2)
    }

    func testVisibleRequestRunsBeforeQueuedPrefetchAndFIFOWithinPriority() async {
        let probe = MediaFetchProbe(delay: .milliseconds(45))
        let loader = MediaPreviewLoader(maximumConcurrentRequests: 1) { key in
            try await probe.fetch(key)
        }
        let blocker = makeKey(messageID: "blocker")
        let prefetch1 = makeKey(messageID: "prefetch-1")
        let prefetch2 = makeKey(messageID: "prefetch-2")
        let visible = makeKey(messageID: "visible")

        let first = Task { await loader.load(blocker, isViewOnce: false, priority: .visible) }
        await waitForCalls(probe, count: 1)
        let second = Task { await loader.load(prefetch1, isViewOnce: false, priority: .prefetch) }
        let third = Task { await loader.load(prefetch2, isViewOnce: false, priority: .prefetch) }
        let fourth = Task { await loader.load(visible, isViewOnce: false, priority: .visible) }
        _ = await (first.value, second.value, third.value, fourth.value)

        let started = await probe.startedMessageIDs
        XCTAssertEqual(
            started,
            ["blocker", "visible", "prefetch-1", "prefetch-2"]
        )
    }

    func testCancellationRemovesQueuedWorkAndLaterRetrySucceeds() async {
        let probe = MediaFetchProbe(delay: .milliseconds(80))
        let loader = MediaPreviewLoader(maximumConcurrentRequests: 1) { key in
            try await probe.fetch(key)
        }
        let blocker = makeKey(messageID: "blocker")
        let cancelled = makeKey(messageID: "cancelled")

        let running = Task { await loader.load(blocker, isViewOnce: false) }
        await waitForCalls(probe, count: 1)
        let pending = Task { await loader.load(cancelled, isViewOnce: false) }
        await waitForQueued(loader, count: 1)
        pending.cancel()
        let cancelledResult = await pending.value
        let cancelledState = await loader.state(for: cancelled)
        let callsBeforeRetry = await probe.callCount(for: cancelled)
        XCTAssertEqual(cancelledResult, .idle)
        XCTAssertEqual(cancelledState, .idle)
        XCTAssertEqual(callsBeforeRetry, 0)

        _ = await running.value
        let retry = await loader.load(cancelled, isViewOnce: false)
        guard case .ready = retry else { return XCTFail("Expected successful retry") }
        let callsAfterRetry = await probe.callCount(for: cancelled)
        XCTAssertEqual(callsAfterRetry, 1)
    }

    func testViewOnceNeverInvokesFetch() async {
        let probe = MediaFetchProbe()
        let loader = MediaPreviewLoader { key in try await probe.fetch(key) }
        let key = makeKey(messageID: "secret")

        let result = await loader.load(key, isViewOnce: true)
        let state = await loader.state(for: key)
        let totalCalls = await probe.totalCalls
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(state, .unavailable)
        XCTAssertEqual(totalCalls, 0)
    }

    func testFailureAndUnavailableAreTypedAndFailureCanRetry() async {
        let failureProbe = MediaFetchProbe(failFirst: true)
        let failureLoader = MediaPreviewLoader { key in try await failureProbe.fetch(key) }
        let key = makeKey(messageID: "retry")

        let firstFailure = await failureLoader.load(key, isViewOnce: false)
        let failureState = await failureLoader.state(for: key)
        XCTAssertEqual(firstFailure, .failed(.transport))
        XCTAssertEqual(failureState, .failed(.transport))
        let retry = await failureLoader.load(key, isViewOnce: false)
        guard case .ready = retry else { return XCTFail("Expected retry after failure") }
        let retryCalls = await failureProbe.callCount(for: key)
        XCTAssertEqual(retryCalls, 2)

        let unavailableLoader = MediaPreviewLoader { _ in
            throw WhatsAppTransportMediaPreviewFailure.unavailable
        }
        let unavailable = makeKey(messageID: "unavailable")
        let unavailableResult = await unavailableLoader.load(unavailable, isViewOnce: false)
        let unavailableState = await unavailableLoader.state(for: unavailable)
        XCTAssertEqual(unavailableResult, .unavailable)
        XCTAssertEqual(unavailableState, .unavailable)
    }

    private func makeKey(
        messageID: String,
        purpose: MediaPreviewPurpose = .attachment,
        size: Int = 768
    ) -> MediaPreviewKey {
        MediaPreviewKey(chatID: "chat", messageID: messageID, purpose: purpose, requestedPixelSize: size)
    }

    private func waitForCalls(_ probe: MediaFetchProbe, count: Int) async {
        for _ in 0..<500 {
            if await probe.totalCalls >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for fetches")
    }

    private func waitForQueued(_ loader: MediaPreviewLoader, count: Int) async {
        for _ in 0..<500 {
            if await loader.queuedRequestCount >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for queued previews")
    }
}

private actor MediaFetchProbe {
    private let delay: Duration
    private let failFirst: Bool
    private var calls: [MediaPreviewKey: Int] = [:]
    private(set) var maximumConcurrent = 0
    private var currentConcurrent = 0
    private(set) var startedMessageIDs: [String] = []

    init(delay: Duration = .zero, failFirst: Bool = false) {
        self.delay = delay
        self.failFirst = failFirst
    }

    var totalCalls: Int { calls.values.reduce(0, +) }

    func callCount(for key: MediaPreviewKey) -> Int { calls[key, default: 0] }

    func fetch(_ key: MediaPreviewKey) async throws -> WhatsAppTransportMediaPreview {
        calls[key, default: 0] += 1
        let thisCall = calls[key, default: 0]
        startedMessageIDs.append(key.messageID)
        currentConcurrent += 1
        maximumConcurrent = max(maximumConcurrent, currentConcurrent)
        defer { currentConcurrent -= 1 }
        if delay > .zero { try await Task.sleep(for: delay) }
        if failFirst && thisCall == 1 { throw ProbeError.failed }
        return WhatsAppTransportMediaPreview(
            mimeType: "image/jpeg",
            data: Data(key.messageID.utf8),
            width: 10,
            height: 10
        )
    }

    private enum ProbeError: Error { case failed }
}
