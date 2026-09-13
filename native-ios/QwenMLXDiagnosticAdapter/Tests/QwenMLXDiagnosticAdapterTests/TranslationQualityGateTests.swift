import XCTest

@testable import QwenMLXDiagnosticAdapter

final class TranslationQualityGateTests: XCTestCase {
    func testNonEmptyOutputAlwaysRequiresHumanReview() {
        let decision = TranslationQualityGate.evaluate(
            sourceText: "Aku sudah sampai di rumah.",
            output: "Już dotarłem do domu."
        )

        XCTAssertEqual(decision.status, .requiresHumanReview)
        XCTAssertEqual(decision.reasons, [.semanticQualityUnverified])
        XCTAssertTrue(decision.requiresHumanReview)
        XCTAssertFalse(decision.mayBeSent)
    }

    func testMissingEmptyInterruptedAndTruncatedOutputsAreBlocked() {
        XCTAssertEqual(
            TranslationQualityGate.evaluate(sourceText: "tekst", output: nil).status,
            .blocked
        )
        XCTAssertEqual(
            TranslationQualityGate.evaluate(sourceText: "tekst", output: "   ").reasons,
            [.emptyOutput]
        )
        XCTAssertEqual(
            TranslationQualityGate.evaluate(
                sourceText: "tekst", output: "częściowy", finishReason: "cancelled"
            ).reasons,
            [.interruptedOutput]
        )
        XCTAssertEqual(
            TranslationQualityGate.evaluate(
                sourceText: "tekst", output: "częściowy", reachedGenerationLimit: true
            ).reasons,
            [.truncatedOutput]
        )
    }

    func testControlTokensAndUnchangedSourceAreBlocked() {
        let controlTokenDecision = TranslationQualityGate.evaluate(
            sourceText: "Aku sudah sampai di rumah.",
            output: "<end_of_turn> Już dotarłem do domu."
        )
        XCTAssertEqual(controlTokenDecision.status, .blocked)
        XCTAssertTrue(controlTokenDecision.reasons.contains(.controlTokenLeakage))

        let unchangedDecision = TranslationQualityGate.evaluate(
            sourceText: "Aku sudah sampai di rumah.",
            output: "  aku   sudah sampai di rumah.  "
        )
        XCTAssertEqual(unchangedDecision.status, .blocked)
        XCTAssertTrue(unchangedDecision.reasons.contains(.unchangedSource))
    }

    func testExecutionMetadataCannotUpgradeAnInterruptedOutput() {
        let decision = TranslationQualityGate.evaluate(
            sourceText: "Kok kamu belum tidur?",
            output: "Dlaczego jeszcze nie",
            termination: .cancelled,
            outputValidity: .interrupted,
            finishReason: "cancelled"
        )

        XCTAssertEqual(decision.status, .blocked)
        XCTAssertEqual(
            decision.reasons,
            [.interruptedOutput, .nonReturnedExecution]
        )
    }
}
