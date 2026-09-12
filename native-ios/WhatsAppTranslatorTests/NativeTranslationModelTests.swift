import XCTest
@testable import WhatsAppBridgeCore

@available(macOS 14, iOS 17, *)
@MainActor
final class NativeTranslationModelTests: XCTestCase {
    private let key = NativeTranslationKey(chatID: "chat", messageID: "message", sourceLanguage: "id", targetLanguage: "pl")
    private let parts: [NativeTranslationPart] = [
        .init(id: "verb", source: "Aku minum", translation: "Piję "),
        .init(id: "coffee", source: "kopi", translation: "kawę"),
        .init(id: "period", source: nil, translation: ".")
    ]

    func testKnownWordsPreserveOriginalAndPunctuation() async throws {
        let model = NativeTranslationModel()
        model.seedSample(key: key, original: "Aku minum kopi.", parts: parts)
        model.toggleKnown("kopi", language: "id")
        let record = try XCTUnwrap(model.record(for: key, original: "Aku minum kopi."))
        XCTAssertEqual(model.displayText(for: record, language: "id"), "Piję kawę.")
        model.showKnownWords = true
        XCTAssertEqual(model.displayText(for: record, language: "id"), "Piję kopi.")
        XCTAssertEqual(model.displayText(for: record, language: "en"), "Piję kawę.")
        model.toggleKnown("KOPI", language: "id")
        XCTAssertEqual(model.displayText(for: record, language: "id"), "Piję kawę.")
        XCTAssertNil(model.record(for: key, original: "Edited source"))
    }

    func testCorrectionPersistsAndRejectsStaleEditor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let model = NativeTranslationModel(fileURL: url)
        model.seedSample(key: key, original: "Aku minum kopi.", parts: parts)
        var correction = parts
        correction[0].translation = "Wypijam "
        XCTAssertTrue(model.saveCorrection(key: key, original: "Aku minum kopi.", parts: correction, expectedRevision: 1))
        XCTAssertFalse(model.saveCorrection(key: key, original: "Aku minum kopi.", parts: parts, expectedRevision: 1))
        model.toggleKnown("kopi", language: "id")
        let restored = NativeTranslationModel(fileURL: url)
        XCTAssertEqual(restored.records[key]?.translatedText, "Wypijam kawę.")
        XCTAssertEqual(restored.records[key]?.original, "Aku minum kopi.")
        XCTAssertTrue(restored.isKnown("kopi", language: "id"))
    }

    func testDisabledEngineSavesCommentWithoutInventingTranslation() async {
        let model = NativeTranslationModel()
        model.seedSample(key: key, original: "Aku minum kopi.", parts: parts)
        await model.retranslate(key: key, original: "Aku minum kopi.", comment: "Keep informal tone")
        XCTAssertEqual(model.records[key]?.comment, "Keep informal tone")
        XCTAssertEqual(model.records[key]?.translatedText, "Piję kawę.")
        XCTAssertTrue(model.notices[key]?.contains("No model was run") == true)
    }

    func testCommentIsForwardedToInjectedTranslator() async {
        let provider = CapturingNativeRetranslator()
        let model = NativeTranslationModel(retranslator: provider)
        model.seedSample(key: key, original: "Aku minum kopi.", parts: parts)
        await model.retranslate(key: key, original: "Aku minum kopi.", comment: "  More natural  ")
        let request = await provider.request
        XCTAssertEqual(request?.comment, "More natural")
        XCTAssertEqual(request?.original, "Aku minum kopi.")
        XCTAssertEqual(request?.previousTranslation, "Piję kawę.")
        XCTAssertEqual(model.records[key]?.translatedText, "Test result")
        XCTAssertTrue(model.running.isEmpty)
    }

    func testLateRetranslationCannotOverwriteManualCorrection() async {
        let provider = DelayedNativeRetranslator()
        let model = NativeTranslationModel(retranslator: provider)
        model.seedSample(key: key, original: "Aku minum kopi.", parts: parts)
        let task = Task { await model.retranslate(key: key, original: "Aku minum kopi.", comment: "Revise") }
        await provider.waitForRequest()
        let revision = model.records[key]?.revision ?? 0
        XCTAssertTrue(model.saveCorrection(
            key: key, original: "Aku minum kopi.",
            parts: [.init(id: "manual", source: nil, translation: "My correction")], expectedRevision: revision
        ))
        await provider.finish()
        await task.value
        XCTAssertEqual(model.records[key]?.translatedText, "My correction")
        XCTAssertTrue(model.records[key]?.manuallyEdited == true)
    }
}

private actor CapturingNativeRetranslator: NativeRetranslator {
    var request: NativeRetranslationRequest?
    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart] {
        self.request = request
        return [.init(id: "result", source: nil, translation: "Test result")]
    }
}

private actor DelayedNativeRetranslator: NativeRetranslator {
    private var pending: CheckedContinuation<[NativeTranslationPart], Never>?
    private var started: CheckedContinuation<Void, Never>?

    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart] {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func finish() {
        pending?.resume(returning: [.init(id: "late", source: nil, translation: "Stale result")])
        pending = nil
    }
}
