import XCTest
@testable import WhatsAppBridgeCore

@available(macOS 14, iOS 17, *)
@MainActor
final class NativeChatModelTests: XCTestCase {
    func testStartsWithoutFakeAccountOrChats() {
        let model = NativeChatModel()
        XCTAssertFalse(model.isSample)
        XCTAssertTrue(model.chats.isEmpty)
        model.drafts["unknown"] = "Hello"
        XCTAssertFalse(model.canSend(chatID: "unknown"))
    }

    func testSearchAndFilters() {
        let model = NativeChatModel()
        model.openSamples()
        XCTAssertEqual(model.visibleChats.count, 3)
        model.filter = .unread
        XCTAssertEqual(model.visibleChats.map(\.id), ["sample-alex"])
        model.filter = .groups
        XCTAssertEqual(model.visibleChats.map(\.id), ["sample-weekend"])
        model.filter = .all
        model.search = "NOTES"
        XCTAssertEqual(model.visibleChats.map(\.id), ["sample-notes"])
        model.search = "no matching chat"
        XCTAssertTrue(model.visibleChats.isEmpty)
    }

    func testLocalReplyAndWhitespaceValidation() async {
        let model = NativeChatModel()
        model.openSamples()
        let chatID = "sample-alex"
        model[draft: chatID] = " \n "
        XCTAssertFalse(model.canSend(chatID: chatID))
        model.quotes[chatID] = model.messages[chatID]?.first
        let quoteID = model.quotes[chatID]?.id
        model[draft: chatID] = "A local reply"
        await model.send(chatID: chatID)
        let reply = model.messages[chatID]?.first { $0.body == "A local reply" }
        XCTAssertEqual(reply?.quote?.messageID, quoteID)
        XCTAssertEqual(reply?.fromMe, true)
        XCTAssertEqual(model[draft: chatID], "")
        XCTAssertNil(model.quotes[chatID])
        XCTAssertTrue(model.sending.isEmpty)
    }

    func testDraftsAreIndependentAndSamplesDoNotReset() async {
        let model = NativeChatModel()
        model.openSamples()
        model[draft: "sample-alex"] = "First draft"
        model[draft: "sample-notes"] = "Second draft"
        await model.send(chatID: "sample-alex")
        XCTAssertEqual(model[draft: "sample-notes"], "Second draft")
        model.openSamples()
        XCTAssertEqual(model.messages["sample-alex"]?.count, 3)
    }

    func testUnconfirmedSendPreservesDraftAndQuote() async throws {
        let model = NativeChatModel(transport: FailingNativeTransport())
        try await model.connect()
        model[draft: "test-chat"] = "Keep this draft"
        model.quotes["test-chat"] = .init(
            id: "quote", chatID: "test-chat", senderID: nil, timestampMilliseconds: 1,
            body: "Original", fromMe: false, quote: nil, media: nil
        )
        await model.send(chatID: "test-chat")
        XCTAssertEqual(model[draft: "test-chat"], "Keep this draft")
        XCTAssertEqual(model.quotes["test-chat"]?.id, "quote")
        XCTAssertNotNil(model.errors["test-chat"])
        XCTAssertTrue(model.sending.isEmpty)
        XCTAssertNil(model.messages["test-chat"])
        model.openSamples()
        XCTAssertFalse(model.isSample)
    }
}

private struct FailingNativeTransport: WhatsAppTransport {
    func connect() async throws {}
    func connectionState() async throws -> WhatsAppTransportConnectionState { .ready }
    func listChats() async throws -> [WhatsAppTransportChat] {
        [.init(id: "test-chat", title: "Test", isGroup: false,
               unreadCount: 0, lastMessageTimestampMilliseconds: nil)]
    }
    func loadMessages(chatID: String, cursor: WhatsAppTransportMessageCursor?,
                      limit: Int) async throws -> WhatsAppTransportMessagePage {
        .init(messages: [], nextCursor: nil)
    }
    func sendText(_ text: String, to chatID: String) async throws -> WhatsAppTransportMessage {
        throw WhatsAppWebTransportError.bridgeUnavailable("test-offline")
    }
    func reply(_ text: String, to messageID: String, in chatID: String) async throws -> WhatsAppTransportMessage {
        throw WhatsAppWebTransportError.bridgeUnavailable("test-offline")
    }
    func eventStream() async -> AsyncStream<WhatsAppTransportEvent> { AsyncStream { $0.finish() } }
}
