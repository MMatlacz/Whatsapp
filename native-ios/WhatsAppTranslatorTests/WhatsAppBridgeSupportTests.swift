import Foundation
import XCTest
@testable import WhatsAppBridgeCore

final class WhatsAppBridgeSupportTests: XCTestCase {
    func testPairingCodeParserNormalizesValidCode() {
        let result = WhatsAppBridgeResultParser.pairingCode(
            from: ["status": "pairing-code-found", "code": "ab12-cd34"]
        )

        XCTAssertEqual(result, WhatsAppPairingCodeResult(status: "pairing-code-found", code: "AB12CD34"))
    }

    func testPairingCodeParserReturnsNoCodeWhenNotFound() {
        let result = WhatsAppBridgeResultParser.pairingCode(
            from: ["status": "pairing-code-not-found"]
        )

        XCTAssertEqual(result, WhatsAppPairingCodeResult(status: "pairing-code-not-found", code: nil))
    }

    func testPairingCodeParserRejectsMalformedCode() {
        XCTAssertNil(
            WhatsAppBridgeResultParser.pairingCode(
                from: ["status": "pairing-code-found", "code": "too-short"]
            )
        )
        XCTAssertNil(
            WhatsAppBridgeResultParser.pairingCode(
                from: ["status": "pairing-code-found", "code": "TOO-SHORT"]
            )
        )
        XCTAssertNil(
            WhatsAppBridgeResultParser.pairingCode(
                from: ["status": "pairing-code-found", "code": "ABCD💥123"]
            )
        )
    }

    func testPairingCodeParserRejectsUnknownStatusAndPayloadShape() {
        XCTAssertNil(
            WhatsAppBridgeResultParser.pairingCode(
                from: ["status": "pairing-code-secret", "code": "ABCD1234"]
            )
        )
        XCTAssertNil(WhatsAppBridgeResultParser.pairingCode(from: "ABCD1234"))
        XCTAssertNil(WhatsAppBridgeResultParser.pairingCode(from: nil))
    }

    func testStatusParserWhitelistsPhoneLinkStates() {
        XCTAssertEqual(
            WhatsAppBridgeResultParser.status(
                from: ["status": "phone-link-entry-clicked"],
                allowed: WhatsAppBridgeResultParser.phoneLinkStatuses
            ),
            "phone-link-entry-clicked"
        )
        XCTAssertEqual(
            WhatsAppBridgeResultParser.status(
                from: ["status": "phone-link-entry-not-found"],
                allowed: WhatsAppBridgeResultParser.phoneLinkStatuses
            ),
            "phone-link-entry-not-found"
        )
        XCTAssertNil(
            WhatsAppBridgeResultParser.status(
                from: ["status": "javascript-injected-arbitrary-state"],
                allowed: WhatsAppBridgeResultParser.phoneLinkStatuses
            )
        )
    }

    func testStatusParserWhitelistsSessionClassifications() {
        for expected in [
            "authenticated-ui-heuristic",
            "authentication-ui-heuristic",
            "unknown-ui",
        ] {
            XCTAssertEqual(
                WhatsAppBridgeResultParser.status(
                    from: ["status": expected],
                    allowed: WhatsAppBridgeResultParser.sessionStatuses
                ),
                expected
            )
        }

        XCTAssertNil(
            WhatsAppBridgeResultParser.status(
                from: ["status": "definitely-authenticated"],
                allowed: WhatsAppBridgeResultParser.sessionStatuses
            )
        )
    }

    func testPrimitiveParserHandlesBoolAndNSNumberValues() {
        let result = WhatsAppBridgeResultParser.primitives(
            from: [
                "indexedDB": true,
                "webSocket": NSNumber(value: true),
                "cryptoSubtle": false,
                "serviceWorker": NSNumber(value: false),
            ]
        )

        XCTAssertEqual(
            result,
            BrowserPrimitiveStatus(
                indexedDB: true,
                webSocket: true,
                cryptoSubtle: false,
                serviceWorker: false
            )
        )
    }

    func testPrimitiveParserKeepsUnknownFieldsUnknownAndRejectsWrongContainer() {
        let result = WhatsAppBridgeResultParser.primitives(
            from: ["indexedDB": "yes", "webSocket": true]
        )

        XCTAssertEqual(
            result,
            BrowserPrimitiveStatus(
                indexedDB: nil,
                webSocket: true,
                cryptoSubtle: nil,
                serviceWorker: nil
            )
        )
        XCTAssertNil(WhatsAppBridgeResultParser.primitives(from: ["not", "a", "dictionary"]))
    }

    func testNewLoadResetClearsTransientPairingAndStartsLoading() {
        let reset = WhatsAppSessionResetValues.newLoad

        XCTAssertNil(reset.pairingCode)
        XCTAssertEqual(reset.pairingFlowState, "not started")
        XCTAssertEqual(reset.sessionState, "not evaluated")
        XCTAssertEqual(reset.disconnectState, "not requested")
        XCTAssertEqual(reset.loadState, "starting")
        XCTAssertTrue(reset.isLoading)
    }

    func testDisconnectResetClearsTransientPairingAndStopsLoading() {
        let reset = WhatsAppSessionResetValues.disconnect

        XCTAssertNil(reset.pairingCode)
        XCTAssertEqual(reset.pairingFlowState, "cleared")
        XCTAssertEqual(reset.sessionState, "not evaluated")
        XCTAssertEqual(reset.disconnectState, "releasing WebKit session")
        XCTAssertEqual(reset.loadState, "not started")
        XCTAssertFalse(reset.isLoading)
    }

    func testDiagnosticsBufferIsBoundedAndTruncatesMessages() {
        var diagnostics: [String] = []

        for index in 0..<25 {
            diagnostics = WhatsAppDiagnosticsBuffer.appending(
                "message-\(index)-" + String(repeating: "x", count: 600),
                to: diagnostics
            )
        }

        XCTAssertEqual(diagnostics.count, WhatsAppDiagnosticsBuffer.defaultLimit)
        XCTAssertTrue(diagnostics.first?.hasPrefix("message-5-") == true)
        XCTAssertEqual(diagnostics.last?.count, WhatsAppDiagnosticsBuffer.defaultMessageLimit)
    }

    func testDiagnosticsBufferHandlesDisabledLimits() {
        XCTAssertEqual(
            WhatsAppDiagnosticsBuffer.appending("message", to: ["old"], limit: 0),
            []
        )
        XCTAssertEqual(
            WhatsAppDiagnosticsBuffer.appending("message", to: ["old"], messageLimit: 0),
            []
        )
    }

    func testProfileIdentifierIsStable() {
        XCTAssertEqual(
            WhatsAppSessionContract.profileIdentifier.uuidString,
            "6F856F49-F202-4637-946A-75075B7A2A22"
        )
    }
}
