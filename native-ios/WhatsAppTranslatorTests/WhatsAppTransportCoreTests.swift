import Foundation
import XCTest
@testable import WhatsAppBridgeCore

final class WhatsAppTransportCoreTests: XCTestCase {
    func testMessageEventDecodesIntoStableDTO() throws {
        let event = try WhatsAppBridgeDecoder.decodeEvent(
            from: json(
                """
                {
                  "version": 1,
                  "kind": "message",
                  "payload": {
                    "id": "m1",
                    "chatID": "group-1",
                    "senderID": "participant-1",
                    "timestampMilliseconds": 123,
                    "body": "halo",
                    "fromMe": false,
                    "deliveryState": "read",
                    "quote": {
                      "messageID": "m0",
                      "senderID": "participant-2",
                      "body": "quoted"
                    },
                    "media": {
                      "kind": "image",
                      "mimeType": "image/jpeg",
                      "filename": null,
                      "sizeBytes": 2048,
                      "durationMilliseconds": null,
                      "width": 640,
                      "height": 480
                    }
                  }
                }
                """
            )
        )

        XCTAssertEqual(
            event,
            .message(
                WhatsAppTransportMessage(
                    id: "m1",
                    chatID: "group-1",
                    senderID: "participant-1",
                    timestampMilliseconds: 123,
                    body: "halo",
                    fromMe: false,
                    quote: WhatsAppTransportQuote(
                        messageID: "m0",
                        senderID: "participant-2",
                        body: "quoted"
                    ),
                    media: WhatsAppTransportMediaMetadata(
                        kind: .image,
                        mimeType: "image/jpeg",
                        filename: nil,
                        sizeBytes: 2048,
                        durationMilliseconds: nil,
                        width: 640,
                        height: 480
                    ),
                    deliveryState: .read
                )
            )
        )
    }

    func testUnsupportedBridgeVersionIsRejected() {
        XCTAssertThrowsError(
            try WhatsAppBridgeDecoder.decodeEvent(
                from: json(#"{"version":2,"kind":"ready","payload":{}}"#)
            )
        ) { error in
            XCTAssertEqual(error as? WhatsAppBridgeDecodingError, .unsupportedVersion(2))
        }
    }

    func testUnknownEventAndResponseKindsAreRejected() {
        XCTAssertThrowsError(
            try WhatsAppBridgeDecoder.decodeEvent(
                from: json(#"{"version":1,"kind":"rawInternalThing","payload":{}}"#)
            )
        ) { error in
            XCTAssertEqual(
                error as? WhatsAppBridgeDecodingError,
                .unknownEventKind("rawInternalThing")
            )
        }

        XCTAssertThrowsError(
            try WhatsAppBridgeDecoder.decodeResponse(
                from: json(#"{"version":1,"kind":"privateStoreDump","payload":{}}"#)
            )
        ) { error in
            XCTAssertEqual(
                error as? WhatsAppBridgeDecodingError,
                .unknownResponseKind("privateStoreDump")
            )
        }
    }

    func testMalformedMessagePayloadIsRejected() {
        XCTAssertThrowsError(
            try WhatsAppBridgeDecoder.decodeEvent(
                from: json(
                    """
                    {
                      "version": 1,
                      "kind": "message",
                      "payload": {
                        "id": "",
                        "chatID": "group-1",
                        "senderID": null,
                        "timestampMilliseconds": -1,
                        "body": null,
                        "fromMe": false,
                        "quote": null,
                        "media": null
                      }
                    }
                    """
                )
            )
        ) { error in
            XCTAssertEqual(error as? WhatsAppBridgeDecodingError, .invalidPayload("message"))
        }
    }

    func testChatAndMessageResponsesDecode() throws {
        let chats = try WhatsAppBridgeDecoder.decodeResponse(
            from: json(
                """
                {
                  "version": 1,
                  "kind": "listChats",
                  "payload": {
                    "chats": [
                      {
                        "id": "group-1",
                        "title": "Family",
                        "isGroup": true,
                        "unreadCount": 2,
                        "lastMessageTimestampMilliseconds": 123
                      }
                    ]
                  }
                }
                """
            )
        )

        XCTAssertEqual(
            chats,
            .chats(
                [
                    WhatsAppTransportChat(
                        id: "group-1",
                        title: "Family",
                        isGroup: true,
                        unreadCount: 2,
                        lastMessageTimestampMilliseconds: 123
                    ),
                ]
            )
        )

        let messages = try WhatsAppBridgeDecoder.decodeResponse(
            from: json(
                """
                {
                  "version": 1,
                  "kind": "loadMessages",
                  "payload": {
                    "messages": [],
                    "nextCursor": {
                      "beforeMessageID": "m0",
                      "beforeTimestampMilliseconds": 100
                    }
                  }
                }
                """
            )
        )

        XCTAssertEqual(
            messages,
            .messages(
                WhatsAppTransportMessagePage(
                    messages: [],
                    nextCursor: WhatsAppTransportMessageCursor(
                        beforeMessageID: "m0",
                        beforeTimestampMilliseconds: 100
                    )
                )
            )
        )
    }

    func testHistorySyncRejectsMessagesFromAnotherChat() {
        XCTAssertThrowsError(
            try WhatsAppBridgeDecoder.decodeEvent(
                from: json(
                    """
                    {
                      "version": 1,
                      "kind": "historySync",
                      "payload": {
                        "chatID": "group-1",
                        "messages": [
                          {
                            "id": "m1",
                            "chatID": "group-2",
                            "senderID": "participant-1",
                            "timestampMilliseconds": 123,
                            "body": "halo",
                            "fromMe": false,
                            "quote": null,
                            "media": null
                          }
                        ],
                        "nextCursor": null
                      }
                    }
                    """
                )
            )
        ) { error in
            XCTAssertEqual(error as? WhatsAppBridgeDecodingError, .invalidPayload("historySync"))
        }
    }

    func testTransportCanBeReplacedBehindProtocol() async throws {
        let transport: any WhatsAppTransport = StubWhatsAppTransport()

        try await transport.connect()
        let state = try await transport.connectionState()
        let chats = try await transport.listChats()
        let sent = try await transport.sendText("hello", to: "group-1")

        XCTAssertEqual(state, .ready)
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(sent.body, "hello")
        XCTAssertTrue(sent.fromMe)
    }

    private func json(_ value: String) -> Data {
        Data(value.utf8)
    }
}

private actor StubWhatsAppTransport: WhatsAppTransport {
    func connect() async throws {}

    func connectionState() async throws -> WhatsAppTransportConnectionState {
        .ready
    }

    func listChats() async throws -> [WhatsAppTransportChat] {
        [
            WhatsAppTransportChat(
                id: "group-1",
                title: "Family",
                isGroup: true,
                unreadCount: 0,
                lastMessageTimestampMilliseconds: nil
            ),
        ]
    }

    func loadMessages(
        chatID: String,
        cursor: WhatsAppTransportMessageCursor?,
        limit: Int
    ) async throws -> WhatsAppTransportMessagePage {
        WhatsAppTransportMessagePage(messages: [], nextCursor: nil)
    }

    func sendText(_ text: String, to chatID: String) async throws -> WhatsAppTransportMessage {
        WhatsAppTransportMessage(
            id: "sent-1",
            chatID: chatID,
            senderID: "me",
            timestampMilliseconds: 1,
            body: text,
            fromMe: true,
            quote: nil,
            media: nil
        )
    }

    func reply(
        _ text: String,
        to messageID: String,
        in chatID: String
    ) async throws -> WhatsAppTransportMessage {
        WhatsAppTransportMessage(
            id: "reply-1",
            chatID: chatID,
            senderID: "me",
            timestampMilliseconds: 2,
            body: text,
            fromMe: true,
            quote: WhatsAppTransportQuote(
                messageID: messageID,
                senderID: nil,
                body: nil
            ),
            media: nil
        )
    }

    func eventStream() async -> AsyncStream<WhatsAppTransportEvent> {
        AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        }
    }
}
