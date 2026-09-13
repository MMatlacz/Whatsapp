import XCTest
@testable import WhatsAppBridgeCore
import PersistenceCore
import WhatsAppDomainCore

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

    func testExperimentalFirstTranslationRequiresOptInAndInstalledProvider() async {
        let model = NativeTranslationModel()
        await model.translate(key: key, original: "Aku minum kopi.")
        XCTAssertTrue(model.notices[key]?.contains("Automatic translation is disabled") == true)
        XCTAssertNil(model.records[key])
        model.experimentalTranslationEnabled = true
        await model.translate(key: key, original: "Aku minum kopi.")
        XCTAssertTrue(model.notices[key]?.contains("No model was run") == true)
        XCTAssertNil(model.records[key])
    }

    func testOwnerApprovedExperimentalProviderCanTranslate() async {
        let provider = UnvalidatedNativeRetranslator()
        let model = NativeTranslationModel(retranslator: provider)
        model.experimentalTranslationEnabled = true
        model.ownerApprovedExperimentalProvider = true

        await model.translate(key: key, original: "Aku minum kopi.")

        let calls = await provider.count()
        XCTAssertEqual(model.records[key]?.translatedText, "must not run")
        XCTAssertEqual(calls, 1)
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

    func testSQLiteStoreRestoresMappingsCommentsAndKnownWords() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-translation-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let contextStore = try SQLiteContextStore(path: url.path)
        let chatID = try XCTUnwrap(WhatsAppChatID("chat"))
        let messageID = try XCTUnwrap(WhatsAppMessageID("message"))
        try contextStore.core.upsert(chat: try XCTUnwrap(WhatsAppChat(
            id: chatID, title: "Family", kind: .group, unreadCount: 0, lastMessageAt: nil
        )))
        try contextStore.core.upsert(message: WhatsAppMessage(
            id: messageID, chatID: chatID, senderID: nil,
            timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1_000)),
            body: "Aku minum kopi.", fromMe: false, quote: nil, media: nil, translation: nil
        ))

        let model = NativeTranslationModel(contextStore: contextStore)
        XCTAssertTrue(model.saveCorrection(
            key: key, original: "Aku minum kopi.", parts: parts, expectedRevision: 0
        ))
        model.toggleKnown("kopi", language: "id")
        await model.retranslate(key: key, original: "Aku minum kopi.", comment: "Keep the informal tone")

        let restored = NativeTranslationModel(contextStore: try SQLiteContextStore(path: url.path))
        let record = try XCTUnwrap(restored.record(for: key, original: "Aku minum kopi."))
        XCTAssertEqual(record.comment, "Keep the informal tone")
        XCTAssertEqual(record.parts, parts)
        XCTAssertTrue(record.manuallyEdited)
        XCTAssertTrue(restored.isKnown("KOPI", language: "ID"))
        restored.showKnownWords = true
        XCTAssertEqual(restored.displayText(for: record, language: "id"), "Piję kopi.")
    }

    func testLegacyImportRetainsUntouchedRecordsAndWordsAfterEditingOne() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-translation-migration-\(UUID().uuidString)")
        let databaseURL = root.appendingPathComponent("chats.sqlite")
        let legacyURL = root.appendingPathComponent("edits-v1.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let contextStore = try SQLiteContextStore(path: databaseURL.path)
        let chatID = try XCTUnwrap(WhatsAppChatID("chat"))
        let firstMessageID = try XCTUnwrap(WhatsAppMessageID("message"))
        let secondMessageID = try XCTUnwrap(WhatsAppMessageID("message-2"))
        try contextStore.core.upsert(chat: try XCTUnwrap(WhatsAppChat(
            id: chatID, title: "Family", kind: .group, unreadCount: 0, lastMessageAt: nil
        )))
        for (messageID, body) in [
            (firstMessageID, "Aku minum kopi."),
            (secondMessageID, "Dia lagi di jalan.")
        ] {
            try contextStore.core.upsert(message: WhatsAppMessage(
                id: messageID, chatID: chatID, senderID: nil,
                timestamp: try XCTUnwrap(WhatsAppTimestamp(millisecondsSince1970: 1_000)),
                body: body, fromMe: false, quote: nil, media: nil, translation: nil
            ))
        }

        let secondKey = NativeTranslationKey(
            chatID: chatID.rawValue, messageID: secondMessageID.rawValue,
            sourceLanguage: "id", targetLanguage: "pl"
        )
        let secondParts = [
            NativeTranslationPart(id: "subject", source: "Dia lagi", translation: "Ona jest "),
            NativeTranslationPart(id: "place", source: "di jalan", translation: "w drodze"),
            NativeTranslationPart(id: "period", source: nil, translation: ".")
        ]
        let firstRecord = NativeTranslationRecord(
            original: "Aku minum kopi.", parts: parts, revision: 1,
            manuallyEdited: true, comment: "legacy correction"
        )
        let secondRecord = NativeTranslationRecord(
            original: "Dia lagi di jalan.", parts: secondParts, revision: 1,
            manuallyEdited: false, comment: "legacy context"
        )
        let snapshot = LegacyTranslationSnapshotFixture(
            version: 1,
            records: [key: firstRecord, secondKey: secondRecord],
            knownWords: ["id\u{0}kopi", "id\u{0}jalan"]
        )
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: legacyURL, options: .atomic)

        let model = NativeTranslationModel(fileURL: legacyURL, contextStore: contextStore)
        XCTAssertNil(model.storageError)
        XCTAssertEqual(model.records.count, 2)
        XCTAssertEqual(model.records[key]?.comment, "legacy correction")
        XCTAssertEqual(model.records[secondKey]?.translatedText, "Ona jest w drodze.")
        XCTAssertTrue(model.isKnown("KOPI", language: "ID"))
        XCTAssertTrue(model.isKnown("jalan", language: "id"))
        XCTAssertEqual(try contextStore.allTranslations().count, 2)

        var editedParts = parts
        editedParts[0].translation = "Wypijam "
        XCTAssertTrue(model.saveCorrection(
            key: key, original: "Aku minum kopi.", parts: editedParts, expectedRevision: 1
        ))

        let reopenedStore = try SQLiteContextStore(path: databaseURL.path)
        let reopened = NativeTranslationModel(fileURL: legacyURL, contextStore: reopenedStore)
        XCTAssertNil(reopened.storageError)
        XCTAssertEqual(reopened.records[key]?.translatedText, "Wypijam kawę.")
        XCTAssertEqual(reopened.records[key]?.comment, "legacy correction")
        XCTAssertEqual(reopened.records[secondKey]?.translatedText, "Ona jest w drodze.")
        XCTAssertEqual(reopened.records[secondKey]?.comment, "legacy context")
        XCTAssertTrue(reopened.isKnown("kopi", language: "id"))
        XCTAssertTrue(reopened.isKnown("jalan", language: "id"))
        XCTAssertEqual(try reopenedStore.allTranslations().count, 3)
    }

    func testUnvalidatedProviderNeverRunsAndInvalidMappingsAreRejected() async {
        let provider = UnvalidatedNativeRetranslator()
        let model = NativeTranslationModel(retranslator: provider)
        model.experimentalTranslationEnabled = true
        await model.translate(key: key, original: "Aku minum kopi.")
        let calls = await provider.count()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.records[key])

        let invalid = [
            NativeTranslationPart(id: "coffee", source: "kopi", translation: "kawę"),
            NativeTranslationPart(id: "verb", source: "Aku minum", translation: "Piję")
        ]
        XCTAssertFalse(model.saveCorrection(key: key, original: "Aku minum kopi.", parts: invalid, expectedRevision: 0))
        XCTAssertNil(model.records[key])
    }
}

private actor CapturingNativeRetranslator: NativeRetranslator {
    nonisolated let isValidated = true
    var request: NativeRetranslationRequest?
    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart] {
        self.request = request
        return [.init(id: "result", source: nil, translation: "Test result")]
    }
}

private actor DelayedNativeRetranslator: NativeRetranslator {
    nonisolated let isValidated = true
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

private actor UnvalidatedNativeRetranslator: NativeRetranslator {
    private(set) var callCount = 0

    func count() -> Int { callCount }

    func retranslate(_ request: NativeRetranslationRequest) async throws -> [NativeTranslationPart] {
        callCount += 1
        return [.init(id: "unexpected", source: nil, translation: "must not run")]
    }
}

private struct LegacyTranslationSnapshotFixture: Codable {
    let version: Int
    let records: [NativeTranslationKey: NativeTranslationRecord]
    let knownWords: Set<String>
}
