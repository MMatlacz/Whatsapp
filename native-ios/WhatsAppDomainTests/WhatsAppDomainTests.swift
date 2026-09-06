import XCTest
@testable import WhatsAppDomainCore

final class WhatsAppDomainTests: XCTestCase {
    func testStrongIdentifiersRejectBlankValues() {
        XCTAssertNil(WhatsAppChatID(""))
        XCTAssertNil(WhatsAppMessageID("   "))
        XCTAssertNil(WhatsAppParticipantID("\n"))
        XCTAssertEqual(WhatsAppChatID("chat-1")?.rawValue, "chat-1")
    }

    func testTimestampRejectsNegativeMillisecondsAndPreservesPrecision() {
        XCTAssertNil(WhatsAppTimestamp(millisecondsSince1970: -1))

        let timestamp = WhatsAppTimestamp(millisecondsSince1970: 1_234)!
        XCTAssertEqual(timestamp.millisecondsSince1970, 1_234)
        XCTAssertEqual(timestamp.date.timeIntervalSince1970, 1.234, accuracy: 0.000_001)
    }

    func testChatAndCursorEnforceDomainInvariants() {
        let chatID = WhatsAppChatID("chat-1")!
        let messageID = WhatsAppMessageID("m1")!
        let timestamp = WhatsAppTimestamp(millisecondsSince1970: 5_000)!

        XCTAssertNil(
            WhatsAppChat(
                id: chatID,
                title: "Family",
                kind: .group,
                unreadCount: -1,
                lastMessageAt: timestamp
            )
        )
        XCTAssertNil(
            WhatsAppMessageCursor(
                beforeMessageID: nil,
                beforeTimestamp: nil
            )
        )
        XCTAssertNotNil(
            WhatsAppMessageCursor(
                beforeMessageID: messageID,
                beforeTimestamp: nil
            )
        )
    }

    func testMediaAndTranslationMetadataValidateWithoutModelCoupling() {
        XCTAssertNil(
            WhatsAppMediaMetadata(
                kind: .image,
                mimeType: "image/jpeg",
                filename: nil,
                sizeBytes: -1,
                durationMilliseconds: nil,
                width: 10,
                height: 10
            )
        )
        XCTAssertNil(
            WhatsAppTranslationMetadata(
                sourceLanguage: "id",
                targetLanguage: " ",
                translatedBody: "Cześć",
                contextMessageCount: 3,
                translatedAt: nil
            )
        )
        XCTAssertNil(
            WhatsAppTranslationMetadata(
                sourceLanguage: "id",
                targetLanguage: "pl",
                translatedBody: "Cześć",
                contextMessageCount: -1,
                translatedAt: nil
            )
        )

        let metadata = WhatsAppTranslationMetadata(
            sourceLanguage: "id",
            targetLanguage: "pl",
            translatedBody: "Cześć",
            contextMessageCount: 3,
            translatedAt: WhatsAppTimestamp(millisecondsSince1970: 10_000)
        )
        XCTAssertEqual(metadata?.sourceLanguage, "id")
        XCTAssertEqual(metadata?.targetLanguage, "pl")
        XCTAssertEqual(metadata?.contextMessageCount, 3)
    }

    func testParticipantIsIndependentFromTransportDetails() {
        let participant = WhatsAppParticipant(
            id: WhatsAppParticipantID("participant-1")!,
            displayName: "Cindy"
        )
        XCTAssertEqual(participant.id.rawValue, "participant-1")
        XCTAssertEqual(participant.displayName, "Cindy")
    }
}
