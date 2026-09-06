import XCTest
@testable import WhatsAppTranslator

final class WhatsAppSessionInterpreterTests: XCTestCase {
    func testStatusAcceptsKnownAndUnknownValues() {
        XCTAssertEqual(
            WhatsAppSessionInterpreter.status(from: ["status": "authenticated-ui-heuristic"]),
            .value("authenticated-ui-heuristic")
        )
        XCTAssertEqual(
            WhatsAppSessionInterpreter.status(from: ["status": "authentication-ui-heuristic"]),
            .value("authentication-ui-heuristic")
        )
        XCTAssertEqual(
            WhatsAppSessionInterpreter.status(from: ["status": "unknown-ui"]),
            .value("unknown-ui")
        )
    }

    func testStatusRejectsMissingAndMalformedPayloads() {
        XCTAssertEqual(WhatsAppSessionInterpreter.status(from: nil), .malformed)
        XCTAssertEqual(WhatsAppSessionInterpreter.status(from: [:]), .malformed)
        XCTAssertEqual(WhatsAppSessionInterpreter.status(from: ["status": 42]), .malformed)
        XCTAssertEqual(WhatsAppSessionInterpreter.status(from: "authenticated"), .malformed)
    }

    func testPairingCodeNormalizesValidCode() {
        XCTAssertEqual(
            WhatsAppSessionInterpreter.pairingCode(
                from: ["status": "pairing-code-found", "code": "ab12-cd34"]
            ),
            WhatsAppPairingCodeResult(status: "pairing-code-found", code: "AB12CD34")
        )
    }

    func testPairingCodeDoesNotExposeMalformedCode() {
        XCTAssertEqual(
            WhatsAppSessionInterpreter.pairingCode(
                from: ["status": "pairing-code-found", "code": "TOO-SHORT"]
            ),
            WhatsAppPairingCodeResult(status: "pairing-code-found", code: nil)
        )
        XCTAssertNil(WhatsAppSessionInterpreter.pairingCode(from: ["code": "AB12CD34"]))
    }

    func testNonCodeStatusCannotLeakCode() {
        XCTAssertEqual(
            WhatsAppSessionInterpreter.pairingCode(
                from: ["status": "pairing-code-not-found", "code": "AB12CD34"]
            ),
            WhatsAppPairingCodeResult(status: "pairing-code-not-found", code: nil)
        )
    }

    func testDiagnosticsRemainBounded() {
        var diagnostics = BoundedDiagnostics(limit: 3)
        diagnostics.append("one")
        diagnostics.append("two")
        diagnostics.append("three")
        diagnostics.append("four")

        XCTAssertEqual(diagnostics.messages, ["two", "three", "four"])
    }

    func testDedicatedProfileIdentifierIsStable() {
        XCTAssertEqual(
            WhatsAppWebProfile.identifier.uuidString,
            "6F856F49-F202-4637-946A-75075B7A2A22"
        )
    }
}
