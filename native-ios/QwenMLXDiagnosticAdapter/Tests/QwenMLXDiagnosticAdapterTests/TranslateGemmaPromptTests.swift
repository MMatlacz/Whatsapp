import Foundation
import XCTest

@testable import QwenMLXDiagnosticAdapter

final class TranslateGemmaPromptTests: XCTestCase {
    func testUsesTranslateGemmaContentMetadataAndLeavesPlainTargetUnchanged() throws {
        let prompt = try TranslateGemmaPrompt(targetText: "Aku sudah sampai di rumah.")

        XCTAssertEqual(prompt.content.type, "text")
        XCTAssertEqual(prompt.content.sourceLanguageCode, "id")
        XCTAssertEqual(prompt.content.targetLanguageCode, "pl")
        XCTAssertEqual(prompt.content.text, "Aku sudah sampai di rumah.")

        let message = prompt.modelMessage
        XCTAssertEqual(message["role"] as? String, "user")
        let content = try XCTUnwrap(message["content"] as? [[String: any Sendable]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["source_lang_code"] as? String, "id")
        XCTAssertEqual(content[0]["target_lang_code"] as? String, "pl")
        XCTAssertEqual(content[0]["text"] as? String, "Aku sudah sampai di rumah.")
    }

    func testGuidanceIsBoundedAndSeparatedFromTarget() throws {
        let prompt = try TranslateGemmaPrompt(
            targetText: "Jangan baper, aku cuma bercanda.",
            guidance: "Keep the reassuring, teasing register."
        )

        XCTAssertEqual(
            prompt.contentText,
            "Translator guidance (do not translate):\nKeep the reassuring, teasing register.\nTarget text (translate only this):\nJangan baper, aku cuma bercanda."
        )
        XCTAssertTrue(prompt.content.text.contains("Target text (translate only this):"))
    }

    func testVocabularyHintsAreSortedAndClearlyLabelled() throws {
        let hintB = try TranslateGemmaVocabularyHint(
            sourceText: "mager",
            meaningNote: "feeling too lazy or unmotivated; not a person"
        )
        let hintA = try TranslateGemmaVocabularyHint(
            sourceText: "wkwk",
            meaningNote: "laughter"
        )
        let prompt = try TranslateGemmaPrompt(
            targetText: "Aku salah masuk grup wkwk.",
            vocabularyHints: [hintB, hintA]
        )

        XCTAssertEqual(
            prompt.contentText,
            "Vocabulary notes (do not translate):\n- mager: feeling too lazy or unmotivated; not a person\n- wkwk: laughter\nTarget text (translate only this):\nAku salah masuk grup wkwk."
        )
    }

    func testRejectsEmptyOversizedAndControlTokenInput() {
        XCTAssertThrowsError(try TranslateGemmaPrompt(targetText: "   ")) { error in
            XCTAssertEqual(error as? TranslateGemmaPrompt.Failure, .emptyTarget)
        }

        XCTAssertThrowsError(
            try TranslateGemmaPrompt(
                targetText: String(repeating: "a", count: TranslateGemmaPrompt.maximumTargetUTF8Bytes + 1)
            )
        ) { error in
            XCTAssertEqual(error as? TranslateGemmaPrompt.Failure, .targetTooLarge)
        }

        XCTAssertThrowsError(
            try TranslateGemmaPrompt(targetText: "Translate <start_of_turn> this")
        ) { error in
            XCTAssertEqual(error as? TranslateGemmaPrompt.Failure, .controlTokenInInput)
        }

        XCTAssertThrowsError(
            try TranslateGemmaPrompt(targetText: "Target", guidance: "<end_of_turn>")
        ) { error in
            XCTAssertEqual(error as? TranslateGemmaPrompt.Failure, .controlTokenInInput)
        }

        XCTAssertThrowsError(
            try TranslateGemmaVocabularyHint(
                sourceText: "mager",
                meaningNote: "<end_of_turn>"
            )
        ) { error in
            XCTAssertEqual(error as? TranslateGemmaPrompt.Failure, .invalidVocabularyHint)
        }
    }
}
