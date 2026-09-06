import Foundation
import XCTest
@testable import WhatsAppBridgeCore

final class WhatsAppWebTransportTests: XCTestCase {
    func testTransportBuildsStableRequestsAndReturnsTypedResponses() async throws {
        let message = sampleMessage(id: "sent-1")
        let runtime = StubBridgeRuntime { request in
            switch request.kind {
            case .connectionState:
                return try wireResponse(request, kind: "connectionState", payload: ["state": "ready"])
            case .listChats:
                return try wireResponse(request, kind: "listChats", payload: [
                    "chats": [[
                        "id": "group@g.us",
                        "title": "Family",
                        "isGroup": true,
                        "unreadCount": 2
                    ]]
                ])
            case .loadMessages:
                return try wireResponse(request, kind: "loadMessages", payload: [
                    "messages": [try jsonObject(message)],
                    "nextCursor": [
                        "beforeMessageID": "older-1",
                        "beforeTimestampMilliseconds": 1_700_000_000_000
                    ]
                ])
            case .sendText:
                return try wireResponse(
                    request,
                    kind: "sendText",
                    payload: ["message": try jsonObject(message)]
                )
            case .reply:
                return try wireResponse(
                    request,
                    kind: "reply",
                    payload: ["message": try jsonObject(message)]
                )
            }
        }
        let transport = WhatsAppWebTransport(runtime: runtime)

        try await transport.connect()
        let state = try await transport.connectionState()
        let chats = try await transport.listChats()
        let page = try await transport.loadMessages(
            chatID: "group@g.us",
            cursor: WhatsAppTransportMessageCursor(
                beforeMessageID: "cursor-1",
                beforeTimestampMilliseconds: 1_700_000_001_000
            ),
            limit: 25
        )
        let sent = try await transport.sendText("hello", to: "group@g.us")
        let replied = try await transport.reply("reply", to: "quoted-1", in: "group@g.us")
        let connects = await runtime.connectCount()

        XCTAssertEqual(state, .ready)
        XCTAssertEqual(chats.first?.id, "group@g.us")
        XCTAssertEqual(page.messages, [message])
        XCTAssertEqual(sent, message)
        XCTAssertEqual(replied, message)
        XCTAssertEqual(connects, 1)

        let requests = await runtime.capturedRequests()
        XCTAssertEqual(
            requests.map(\.kind),
            [.connectionState, .listChats, .loadMessages, .sendText, .reply]
        )
        XCTAssertEqual(requests[2].payload.chatID, "group@g.us")
        XCTAssertEqual(requests[2].payload.limit, 25)
        XCTAssertEqual(requests[2].payload.cursor?.beforeMessageID, "cursor-1")
        XCTAssertEqual(requests[3].payload.text, "hello")
        XCTAssertEqual(requests[4].payload.messageID, "quoted-1")
        XCTAssertTrue(
            requests.allSatisfy {
                $0.version == WhatsAppBridgeContract.version && !$0.requestID.isEmpty
            }
        )
    }

    func testTransportRejectsInvalidArgumentsWithoutInvokingRuntime() async throws {
        let runtime = StubBridgeRuntime { request in
            try wireResponse(request, kind: "connectionState", payload: ["state": "ready"])
        }
        let transport = WhatsAppWebTransport(runtime: runtime)

        await assertThrows(.invalidArgument("chatID")) {
            _ = try await transport.loadMessages(chatID: " ", cursor: nil, limit: 10)
        }
        await assertThrows(.invalidArgument("limit")) {
            _ = try await transport.loadMessages(chatID: "group@g.us", cursor: nil, limit: 0)
        }
        await assertThrows(.invalidArgument("text")) {
            _ = try await transport.sendText("\n", to: "group@g.us")
        }
        await assertThrows(.invalidArgument("messageID")) {
            _ = try await transport.reply("ok", to: "", in: "group@g.us")
        }

        let requests = await runtime.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testBridgeFailureAndRequestMismatchAreRejected() async throws {
        let failingRuntime = StubBridgeRuntime { request in
            try wireFailure(
                requestID: request.requestID,
                code: "adapter-unavailable",
                message: "not ready"
            )
        }
        let failingTransport = WhatsAppWebTransport(runtime: failingRuntime)
        await assertThrows(.bridgeFailure(code: "adapter-unavailable", message: "not ready")) {
            _ = try await failingTransport.connectionState()
        }

        let mismatchedRuntime = StubBridgeRuntime { request in
            try wireResponse(
                request,
                requestID: "other-request",
                kind: "connectionState",
                payload: ["state": "ready"]
            )
        }
        let mismatchedTransport = WhatsAppWebTransport(runtime: mismatchedRuntime)
        do {
            _ = try await mismatchedTransport.connectionState()
            XCTFail("Expected request mismatch")
        } catch let error as WhatsAppWebTransportError {
            guard case .requestIDMismatch(_, let actual) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(actual, "other-request")
        }
    }

    func testEventStreamForwardsOnlyValidatedEvents() async throws {
        let message = sampleMessage(id: "incoming-1")
        let events = [
            try wireEvent(kind: "ready", payload: [:]),
            Data("not-json".utf8),
            try wireEvent(kind: "message", payload: try jsonObject(message)),
            try wireFailure(requestID: nil, code: "diagnostic", message: "ignored")
        ]
        let runtime = StubBridgeRuntime(events: events) { request in
            try wireResponse(request, kind: "connectionState", payload: ["state": "ready"])
        }
        let transport = WhatsAppWebTransport(runtime: runtime)

        var received: [WhatsAppTransportEvent] = []
        for await event in await transport.eventStream() {
            received.append(event)
        }

        XCTAssertEqual(received, [.ready, .message(message)])
    }

    func testWireDecoderRejectsUnsupportedVersionAndMalformedFailure() throws {
        let unsupported = try JSONSerialization.data(withJSONObject: [
            "bridgeVersion": 99,
            "type": "event",
            "envelope": ["version": 1, "kind": "ready", "payload": [:]]
        ])
        XCTAssertThrowsError(try WhatsAppBridgeWireDecoder.decode(unsupported)) { error in
            XCTAssertEqual(error as? WhatsAppWebTransportError, .unsupportedWireVersion(99))
        }

        let malformed = try JSONSerialization.data(withJSONObject: [
            "bridgeVersion": 1,
            "type": "failure",
            "code": "",
            "message": "bad"
        ])
        XCTAssertThrowsError(try WhatsAppBridgeWireDecoder.decode(malformed)) { error in
            XCTAssertEqual(
                error as? WhatsAppWebTransportError,
                .malformedWireMessage("code")
            )
        }
    }
}

private actor StubBridgeRuntime: WhatsAppWebBridgeRuntime {
    typealias Responder = @Sendable (WhatsAppBridgeRequest) throws -> Data

    private var connects = 0
    private var requests: [WhatsAppBridgeRequest] = []
    private let events: [Data]
    private let responder: Responder

    init(events: [Data] = [], responder: @escaping Responder) {
        self.events = events
        self.responder = responder
    }

    func connect() async throws {
        connects += 1
    }

    func invoke(_ request: WhatsAppBridgeRequest) async throws -> Data {
        requests.append(request)
        return try responder(request)
    }

    func eventStream() async -> AsyncStream<Data> {
        let values = events
        return AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func capturedRequests() -> [WhatsAppBridgeRequest] { requests }
    func connectCount() -> Int { connects }
}

private func sampleMessage(id: String) -> WhatsAppTransportMessage {
    WhatsAppTransportMessage(
        id: id,
        chatID: "group@g.us",
        senderID: "person@c.us",
        timestampMilliseconds: 1_700_000_000_123,
        body: "hello",
        fromMe: false,
        quote: nil,
        media: nil
    )
}

private func wireResponse(
    _ request: WhatsAppBridgeRequest,
    requestID: String? = nil,
    kind: String,
    payload: Any
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "bridgeVersion": 1,
        "type": "response",
        "requestID": requestID ?? request.requestID,
        "envelope": ["version": 1, "kind": kind, "payload": payload]
    ])
}

private func wireEvent(kind: String, payload: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "bridgeVersion": 1,
        "type": "event",
        "envelope": ["version": 1, "kind": kind, "payload": payload]
    ])
}

private func wireFailure(requestID: String?, code: String, message: String) throws -> Data {
    var object: [String: Any] = [
        "bridgeVersion": 1,
        "type": "failure",
        "code": code,
        "message": message
    ]
    if let requestID { object["requestID"] = requestID }
    return try JSONSerialization.data(withJSONObject: object)
}

private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data)
}

private extension WhatsAppWebTransportTests {
    func assertThrows(
        _ expected: WhatsAppWebTransportError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as WhatsAppWebTransportError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
