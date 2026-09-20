import XCTest
@testable import WhatsAppBridgeCore

@available(macOS 14, iOS 17, *)
@MainActor
final class AutomaticTranslationSettingsTests: XCTestCase {
    func testDefaultIsEnabledWithoutPersistedState() async {
        withDefaults { defaults in
            let store = AutomaticTranslationSettingsStore(defaults: defaults)
            XCTAssertTrue(store.globalEnabled)
            XCTAssertEqual(store.override(for: "chat"), .inherit)
            XCTAssertTrue(store.effectiveEnabled(for: "chat"))
        }
    }

    func testGlobalSettingSurvivesRecreation() async {
        withDefaults { defaults in
            let first = AutomaticTranslationSettingsStore(defaults: defaults)
            first.setGlobalEnabled(false)

            let restored = AutomaticTranslationSettingsStore(defaults: defaults)
            XCTAssertFalse(restored.globalEnabled)
            XCTAssertFalse(restored.effectiveEnabled(for: "chat"))
        }
    }

    func testPerChatOverridePersistsTakesPrecedenceAndCanReturnToInherited() async {
        withDefaults { defaults in
            let first = AutomaticTranslationSettingsStore(defaults: defaults)
            first.setGlobalEnabled(false)
            first.setOverride(.enabled, for: "family@g.us")
            first.setOverride(.disabled, for: "quiet@c.us")

            let restored = AutomaticTranslationSettingsStore(defaults: defaults)
            XCTAssertEqual(restored.override(for: "family@g.us"), .enabled)
            XCTAssertTrue(restored.effectiveEnabled(for: "family@g.us"))
            XCTAssertEqual(restored.override(for: "quiet@c.us"), .disabled)
            XCTAssertFalse(restored.effectiveEnabled(for: "quiet@c.us"))
            XCTAssertFalse(restored.effectiveEnabled(for: "inherited@c.us"))

            restored.setOverride(.inherit, for: "family@g.us")
            XCTAssertEqual(restored.override(for: "family@g.us"), .inherit)
            XCTAssertFalse(restored.effectiveEnabled(for: "family@g.us"))
            let afterRemoval = AutomaticTranslationSettingsStore(defaults: defaults)
            XCTAssertEqual(afterRemoval.override(for: "family@g.us"), .inherit)
        }
    }

    func testLegacyGlobalPreferenceMigratesOnce() async {
        withDefaults { defaults in
            defaults.set(false, forKey: "translation.enabled")
            let migrated = AutomaticTranslationSettingsStore(defaults: defaults)
            XCTAssertFalse(migrated.globalEnabled)

            defaults.removeObject(forKey: "translation.enabled")
            let restored = AutomaticTranslationSettingsStore(defaults: defaults)
            XCTAssertFalse(restored.globalEnabled)
        }
    }

    func testSettingsChangesDoNotMutateExistingTranslationRecords() async throws {
        let translations = NativeTranslationModel()
        let key = NativeTranslationKey(
            chatID: "chat", messageID: "message", sourceLanguage: "id", targetLanguage: "pl"
        )
        let parts = [NativeTranslationPart(id: "whole", source: "Halo", translation: "Cześć")]
        translations.seedSample(key: key, original: "Halo", parts: parts)
        let before = try XCTUnwrap(translations.records[key])

        let settings = AutomaticTranslationSettingsStore()
        let model = NativeChatModel(translations: translations, automaticTranslationSettings: settings)
        model.setGlobalAutomaticTranslationEnabled(false)
        model.setAutomaticTranslationOverride(.enabled, for: "chat")
        model.setAutomaticTranslationOverride(.inherit, for: "chat")

        XCTAssertEqual(translations.records[key], before)
        XCTAssertFalse(model.automaticTranslationEnabled(for: "chat"))
    }

    func testModelExposesOneDeterministicEffectiveLookup() async {
        let settings = AutomaticTranslationSettingsStore()
        let model = NativeChatModel(automaticTranslationSettings: settings)

        XCTAssertTrue(model.automaticTranslationEnabled(for: "a"))
        model.setGlobalAutomaticTranslationEnabled(false)
        XCTAssertFalse(model.automaticTranslationEnabled(for: "a"))
        model.setAutomaticTranslationOverride(.enabled, for: "a")
        XCTAssertTrue(model.automaticTranslationEnabled(for: "a"))
        model.setAutomaticTranslationOverride(.disabled, for: "b")
        XCTAssertFalse(model.automaticTranslationEnabled(for: "b"))
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "AutomaticTranslationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
