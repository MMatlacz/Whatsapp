import XCTest
@testable import WhatsAppBridgeCore
import WhatsAppDomainCore

final class WhatsAppTransportDomainMapperTests: XCTestCase {
    func testChatMapsIntoStableDomainType() throws {
        let mapped = try WhatsAppTransportDomainMapper.chat(
            WhatsAppTransportChat(
                id: "group-1",
                title: "Family",
                isGroup: true,
                unreadCount: 2,
                lastMessageTimestampMilliseconds: 123
            )
        )

        XCTAssertEqual(mapped.id, WhatsAppChatID("group-1"))
        XCTAssertEqual(mapped.title, "Family")
        XCTAssertEqual(mapped.kind, .group)
        XCTAssertEqual(mapped.unreadCount, 2)
        XCTAssertEqual(mapped.lastMessageAt?.millisecondsSince1970, 123)
    }

    func testMessageMapsQuoteMediaAndLeavesTranslationUnset() throws {
        let mapped = try WhatsAppTransportDomainMapper.message(
            WhatsAppTransportMessage(
                id: "m1",
                chatID: "group-1",
                senderID: "participant-1",
                timestampMilliseconds: 456,
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
                    filename: "photo.jpg",
                    sizeBytes: 2_048,
                    durationMilliseconds: nil,
                    width: 640,
                    height: 480
                )
            )
        )

        XCTAssertEqual(mapped.id, WhatsAppMessageID("m1"))
        XCTAssertEqual(mapped.chatID, WhatsAppChatID("group-1"))
        XCTAssertEqual(mapped.senderID, WhatsAppParticipantID("participant-1"))
        XCTAssertEqual(mapped.timestamp.millisecondsSince1970, 456)
        XCTAssertEqual(mapped.quote?.messageID, WhatsAppMessageID("m0"))
        XCTAssertEqual(mapped.quote?.senderID, WhatsAppParticipantID("participant-2"))
        XCTAssertEqual(mapped.media?.kind, .image)
        XCTAssertEqual(mapped.media?.sizeBytes, 2_048)
        XCTAssertNil(mapped.translation)
    }

    func testSemanticContentMapsIntoStableDomainCases() throws {
        func mapped(_ content: WhatsAppTransportMessageContent) throws -> WhatsAppMessageContent {
            try WhatsAppTransportDomainMapper.message(WhatsAppTransportMessage(
                id: "m-semantic", chatID: "chat-1", senderID: nil,
                timestampMilliseconds: 1, body: nil, fromMe: false, quote: nil, media: nil,
                content: content
            )).content
        }

        XCTAssertEqual(try mapped(.init(
            kind: .location,
            location: .init(latitude: 52.23, longitude: 21.01, name: "Warsaw", address: "Center")
        )), .location(.init(latitude: 52.23, longitude: 21.01, name: "Warsaw", address: "Center")))
        XCTAssertEqual(try mapped(.init(
            kind: .contact, contacts: [.init(displayName: "Ada", vCard: "BEGIN:VCARD\nEND:VCARD")]
        )), .contact([.init(displayName: "Ada", vCard: "BEGIN:VCARD\nEND:VCARD")]))
        XCTAssertEqual(try mapped(.init(
            kind: .poll, poll: .init(question: "Dinner?", options: ["Yes", "No"])
        )), .poll(.init(question: "Dinner?", options: ["Yes", "No"])))
        XCTAssertEqual(try mapped(.init(kind: .revoked)), .revoked)
        XCTAssertEqual(try mapped(.init(
            kind: .system, system: .init(type: "notification", text: "Alice joined")
        )), .system(.init(type: "notification", text: "Alice joined")))
        XCTAssertEqual(try mapped(.init(kind: .unsupported, rawType: "future_magic")),
                       .unsupported(rawType: "future_magic"))
    }

    func testSemanticContentMappingRejectsOversizedVCard() {
        let message = WhatsAppTransportMessage(
            id: "m-bad", chatID: "chat-1", senderID: nil, timestampMilliseconds: 1,
            body: nil, fromMe: false, quote: nil, media: nil,
            content: .init(kind: .contact, contacts: [
                .init(displayName: "Ada", vCard: String(repeating: "x", count: 4_097))
            ])
        )
        XCTAssertThrowsError(try WhatsAppTransportDomainMapper.message(message)) { error in
            XCTAssertEqual(error as? WhatsAppDomainMappingError, .invalidContent)
        }
    }

    func testMessagePageAndCursorAreStronglyTyped() throws {
        let page = try WhatsAppTransportDomainMapper.page(
            WhatsAppTransportMessagePage(
                messages: [
                    WhatsAppTransportMessage(
                        id: "m1",
                        chatID: "group-1",
                        senderID: nil,
                        timestampMilliseconds: 456,
                        body: "hello",
                        fromMe: true,
                        quote: nil,
                        media: nil
                    ),
                ],
                nextCursor: WhatsAppTransportMessageCursor(
                    beforeMessageID: "m0",
                    beforeTimestampMilliseconds: 400
                )
            )
        )

        XCTAssertEqual(page.messages.first?.id, WhatsAppMessageID("m1"))
        XCTAssertEqual(page.nextCursor?.beforeMessageID, WhatsAppMessageID("m0"))
        XCTAssertEqual(page.nextCursor?.beforeTimestamp?.millisecondsSince1970, 400)

        let transportCursor = WhatsAppTransportDomainMapper.transportCursor(page.nextCursor)
        XCTAssertEqual(transportCursor?.beforeMessageID, "m0")
        XCTAssertEqual(transportCursor?.beforeTimestampMilliseconds, 400)
    }

    func testMapperRejectsInvalidTransportValues() {
        XCTAssertThrowsError(
            try WhatsAppTransportDomainMapper.message(
                WhatsAppTransportMessage(
                    id: "",
                    chatID: "group-1",
                    senderID: nil,
                    timestampMilliseconds: 1,
                    body: nil,
                    fromMe: false,
                    quote: nil,
                    media: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? WhatsAppDomainMappingError, .invalidMessageID(""))
        }

        XCTAssertThrowsError(
            try WhatsAppTransportDomainMapper.cursor(
                WhatsAppTransportMessageCursor(
                    beforeMessageID: nil,
                    beforeTimestampMilliseconds: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? WhatsAppDomainMappingError, .invalidCursor)
        }
    }
}
