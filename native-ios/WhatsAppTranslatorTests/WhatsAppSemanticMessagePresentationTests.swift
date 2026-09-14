import XCTest
@testable import WhatsAppBridgeCore

final class WhatsAppSemanticMessagePresentationTests: XCTestCase {
    func testEverySpecialContentCaseHasDeterministicPresentationAndAccessibilityLabel() throws {
        let fixtures: [(WhatsAppTransportMessageContent, String, String)] = [
            (.init(kind: .location, location: .init(
                latitude: 52.2297, longitude: 21.0122, name: "Warsaw", address: "Center"
            )), "Warsaw", "Location. Warsaw. Center"),
            (.init(kind: .contact, contacts: [
                .init(displayName: "Ayu", vCard: "BEGIN:VCARD\nFN:Ayu\nEND:VCARD")
            ]), "Contact", "Contact. Ayu"),
            (.init(kind: .poll, poll: .init(question: "Lunch?", options: ["Rice", "Soup"])),
             "Lunch?", "Poll. Lunch?. Rice. Soup"),
            (.init(kind: .revoked), "Message deleted", "Message deleted"),
            (.init(kind: .system, system: .init(type: "group-notification", text: "Ayu joined")),
             "Ayu joined", "System message. Ayu joined. group-notification"),
            (.init(kind: .unsupported, rawType: "future-type"),
             "Unsupported WhatsApp message · future-type",
             "Unsupported WhatsApp message · future-type"),
        ]

        for fixture in fixtures {
            let presentation = try XCTUnwrap(WhatsAppSemanticMessagePresenter.presentation(for: fixture.0))
            XCTAssertEqual(presentation.title, fixture.1)
            XCTAssertEqual(presentation.accessibilityLabel, fixture.2)
        }
    }

    func testTextMediaAndLinkPreviewKeepTheirExistingRenderers() {
        XCTAssertNil(WhatsAppSemanticMessagePresenter.presentation(for: .init(kind: .text)))
        XCTAssertNil(WhatsAppSemanticMessagePresenter.presentation(for: .init(kind: .media)))
        XCTAssertNil(WhatsAppSemanticMessagePresenter.presentation(for: .init(kind: .linkPreview)))
    }

    func testPresentationBoundsContactPollAndSystemStrings() throws {
        let contacts = Array(repeating: WhatsAppTransportContactCard(
            displayName: String(repeating: "N", count: 400), vCard: "BEGIN:VCARD\nEND:VCARD"
        ), count: 12)
        let contact = try XCTUnwrap(WhatsAppSemanticMessagePresenter.presentation(
            for: .init(kind: .contact, contacts: contacts)
        ))
        XCTAssertEqual(contact.items.count, 8)
        XCTAssertTrue(contact.items.allSatisfy { $0.count == 256 })

        let poll = try XCTUnwrap(WhatsAppSemanticMessagePresenter.presentation(for: .init(
            kind: .poll,
            poll: .init(
                question: String(repeating: "Q", count: 3_000),
                options: Array(repeating: String(repeating: "O", count: 700), count: 25)
            )
        )))
        XCTAssertEqual(poll.title.count, 2_048)
        XCTAssertEqual(poll.items.count, 20)
        XCTAssertTrue(poll.items.allSatisfy { $0.count == 512 })

        let system = try XCTUnwrap(WhatsAppSemanticMessagePresenter.presentation(for: .init(
            kind: .system,
            system: .init(type: String(repeating: "T", count: 200), text: String(repeating: "S", count: 3_000))
        )))
        XCTAssertEqual(system.title.count, 2_048)
        XCTAssertEqual(system.detail?.count, 128)
    }

    func testUnsupportedPresentationDoesNotPreventAdjacentRows() {
        let contents: [WhatsAppTransportMessageContent] = [
            .init(kind: .text),
            .init(kind: .unsupported, rawType: "new-kind"),
            .init(kind: .system, system: .init(type: "notice", text: "Next row")),
        ]
        let presentations = contents.compactMap(WhatsAppSemanticMessagePresenter.presentation)
        XCTAssertEqual(presentations.map(\.title), [
            "Unsupported WhatsApp message · new-kind",
            "Next row",
        ])
    }
}
