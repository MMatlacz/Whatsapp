import XCTest
import PersistenceCore
import WhatsAppDomainCore
@testable import WhatsAppBridgeCore

@available(macOS 14, iOS 17, *)
@MainActor
final class NativeChatModelTests: XCTestCase {
    func testCachedChatAndHistoryAreReadableWithoutConnectionButCannotSend() async throws {
        let store = try SQLiteWhatsAppStore(path: ":memory:")
        let chat = WhatsAppTransportChat(id: "cache@c.us", title: "Cached chat", isGroup: false,
            unreadCount: 0, lastMessageTimestampMilliseconds: 1000)
        let message = WhatsAppTransportMessage(id: "cached-message", chatID: chat.id, senderID: nil,
            timestampMilliseconds: 1000, body: "Cached text", fromMe: false, quote: nil, media: nil)
        try store.upsert(chat: WhatsAppTransportDomainMapper.chat(chat))
        try store.upsert(message: WhatsAppTransportDomainMapper.message(message))
        let model = NativeChatModel(store: store)
        XCTAssertEqual(model.visibleChats, [chat])
        await model.load(chatID: chat.id)
        XCTAssertEqual(model.messages[chat.id], [message])
        model[draft: chat.id] = "Do not send offline"
        XCTAssertFalse(model.canSend(chatID: chat.id))
        XCTAssertNil(model.storageNotice)
    }

    func testCachedGroupPreviewRestoresSenderName() throws {
        let store = try SQLiteWhatsAppStore(path: ":memory:")
        let chat = WhatsAppTransportChat(id: "family@g.us", title: "Keluarga Panjaitan", isGroup: true,
            unreadCount: 1, lastMessageTimestampMilliseconds: 1000)
        let sender = WhatsAppParticipantID("alice@c.us")!
        let message = WhatsAppTransportMessage(id: "group-message", chatID: chat.id,
            senderID: sender.rawValue, timestampMilliseconds: 1000, body: "Halo semuanya",
            fromMe: false, quote: nil, media: nil)
        try store.upsert(chat: WhatsAppTransportDomainMapper.chat(chat))
        try store.upsert(participant: .init(id: sender, displayName: "Alice"))
        try store.upsert(message: WhatsAppTransportDomainMapper.message(message))

        let model = NativeChatModel(store: store)

        XCTAssertEqual(model.preview(for: chat.id), "Alice: Halo semuanya")
        XCTAssertEqual(model.identities[sender.rawValue]?.name, "Alice")
    }

    func testIdentityPhotoAndNameAreFetchedOnceAndCached() async throws {
        let chat = WhatsAppTransportChat(id: "family@g.us", title: "Keluarga Panjaitan", isGroup: true,
            unreadCount: 0, lastMessageTimestampMilliseconds: nil)
        let senderID = "alice@c.us"
        let provider = RecordingIdentityProvider(identity: .init(name: "Alice", photo: Data([1, 2, 3])))
        let model = NativeChatModel(
            transport: ReadyChatTransport(chat: chat),
            store: try SQLiteWhatsAppStore(path: ":memory:"),
            identityProvider: provider
        )
        try await model.connect()

        await model.loadIdentity(for: senderID)
        await model.loadIdentity(for: senderID)

        XCTAssertEqual(model.identities[senderID], .init(name: "Alice", photo: Data([1, 2, 3])))
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
    }

    func testComposerDraftRestoresAcrossModelRecreation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let model = NativeChatModel(store: try SQLiteWhatsAppStore(path: url.path))
            model[draft: "test@c.us"] = "Unfinished 👋"
            XCTAssertNil(model.storageNotice)
        }
        let restored = NativeChatModel(store: try SQLiteWhatsAppStore(path: url.path))
        XCTAssertEqual(restored[draft: "test@c.us"], "Unfinished 👋")
        restored[draft: "test@c.us"] = ""
        let cleared = NativeChatModel(store: try SQLiteWhatsAppStore(path: url.path))
        XCTAssertEqual(cleared[draft: "test@c.us"], "")
    }

    func testStartsWithoutFakeAccountOrChats() async {
        let model = NativeChatModel()
        XCTAssertFalse(model.isSample)
        XCTAssertTrue(model.chats.isEmpty)
        model.drafts["unknown"] = "Hello"
        XCTAssertFalse(model.canSend(chatID: "unknown"))
    }

    func testSearchAndFilters() async {
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
        model.setReply(model.messages[chatID]?.first, chatID: chatID)
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
        model.setReply(.init(
            id: "quote", chatID: "test-chat", senderID: nil, timestampMilliseconds: 1,
            body: "Original", fromMe: false, quote: nil, media: nil
        ), chatID: "test-chat")
        await model.send(chatID: "test-chat")
        XCTAssertEqual(model[draft: "test-chat"], "Keep this draft")
        XCTAssertEqual(model.quotes["test-chat"]?.id, "quote")
        XCTAssertNotNil(model.errors["test-chat"])
        XCTAssertTrue(model.sending.isEmpty)
        XCTAssertNil(model.messages["test-chat"])
        model.openSamples()
        XCTAssertFalse(model.isSample)
    }

    func testUncertainSendRequiresFreshHistoryAndExplicitResolution() async throws {
        let chat = WhatsAppTransportChat(id: "test-chat", title: "Test", isGroup: false,
            unreadCount: 0, lastMessageTimestampMilliseconds: 1_000)
        let oldSameBody = WhatsAppTransportMessage(
            id: "old-message", chatID: chat.id, senderID: nil, timestampMilliseconds: 1_000,
            body: "Keep this draft", fromMe: true, quote: nil, media: nil
        )
        let model = NativeChatModel(
            transport: ReadyChatTransport(chat: chat, history: [oldSameBody]),
            store: try SQLiteWhatsAppStore(path: ":memory:")
        )
        try await model.connect()
        model[draft: chat.id] = "Keep this draft"

        await model.send(chatID: chat.id)
        XCTAssertTrue(model.uncertainSends.contains(chat.id))
        XCTAssertFalse(model.canSend(chatID: chat.id))

        model.resolveUncertainSend(chatID: chat.id)
        XCTAssertTrue(model.uncertainSends.contains(chat.id))

        await model.load(chatID: chat.id)
        XCTAssertTrue(model.historyCheckedAfterUncertainSends.contains(chat.id))
        XCTAssertFalse(model.canSend(chatID: chat.id))

        model.resolveUncertainSend(chatID: chat.id)
        XCTAssertFalse(model.uncertainSends.contains(chat.id))
        XCTAssertTrue(model.canSend(chatID: chat.id))
    }

    func testReplyAndUncertainSendRestoreAcrossModelRecreation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let chat = WhatsAppTransportChat(id: "restore@c.us", title: "Restore", isGroup: false,
            unreadCount: 0, lastMessageTimestampMilliseconds: 1_000)
        let quoted = WhatsAppTransportMessage(
            id: "quoted", chatID: chat.id, senderID: "contact@c.us", timestampMilliseconds: 1_000,
            body: "Original", fromMe: false, quote: nil, media: nil
        )
        do {
            let store = try SQLiteWhatsAppStore(path: url.path)
            try store.upsert(chat: WhatsAppTransportDomainMapper.chat(chat))
            try store.upsert(message: WhatsAppTransportDomainMapper.message(quoted))
            let model = NativeChatModel(transport: ReadyChatTransport(chat: chat), store: store)
            try await model.connect()
            model[draft: chat.id] = "Keep after relaunch"
            model.setReply(quoted, chatID: chat.id)
            await model.send(chatID: chat.id)
            XCTAssertTrue(model.uncertainSends.contains(chat.id))
        }

        let restored = NativeChatModel(store: try SQLiteWhatsAppStore(path: url.path))
        XCTAssertEqual(restored[draft: chat.id], "Keep after relaunch")
        XCTAssertEqual(restored.quotes[chat.id]?.id, quoted.id)
        XCTAssertTrue(restored.uncertainSends.contains(chat.id))
        XCTAssertFalse(restored.canSend(chatID: chat.id))
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

private struct ReadyChatTransport: WhatsAppTransport {
    let chat: WhatsAppTransportChat
    var history: [WhatsAppTransportMessage] = []

    func connect() async throws {}
    func connectionState() async throws -> WhatsAppTransportConnectionState { .ready }
    func listChats() async throws -> [WhatsAppTransportChat] { [chat] }
    func loadMessages(chatID: String, cursor: WhatsAppTransportMessageCursor?,
                      limit: Int) async throws -> WhatsAppTransportMessagePage {
        .init(messages: history, nextCursor: nil)
    }
    func sendText(_ text: String, to chatID: String) async throws -> WhatsAppTransportMessage {
        throw WhatsAppWebTransportError.bridgeUnavailable("test")
    }
    func reply(_ text: String, to messageID: String, in chatID: String) async throws -> WhatsAppTransportMessage {
        throw WhatsAppWebTransportError.bridgeUnavailable("test")
    }
    func eventStream() async -> AsyncStream<WhatsAppTransportEvent> {
        AsyncStream { _ in }
    }
}

private actor RecordingIdentityProvider: NativeContactIdentityProvider {
    let identity: NativeContactIdentity
    private(set) var callCount = 0

    init(identity: NativeContactIdentity) {
        self.identity = identity
    }

    func identity(for id: String) async throws -> NativeContactIdentity {
        callCount += 1
        return identity
    }
}
