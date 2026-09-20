import Foundation
import Observation

enum AutomaticTranslationOverride: String, Codable, CaseIterable, Equatable, Sendable {
    case inherit
    case enabled
    case disabled
}

@available(iOS 17, macOS 14, *)
@MainActor @Observable
final class AutomaticTranslationSettingsStore {
    static let currentSchemaVersion = 1
    private static let schemaKey = "automaticTranslation.settings.version"
    private static let globalKey = "automaticTranslation.globalEnabled"
    private static let overridesKey = "automaticTranslation.chatOverrides"
    private static let legacyGlobalKey = "translation.enabled"

    private let defaults: UserDefaults?
    private(set) var globalEnabled: Bool
    private(set) var chatOverrides: [String: AutomaticTranslationOverride]

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        guard let defaults else {
            globalEnabled = true
            chatOverrides = [:]
            return
        }

        let storedVersion = defaults.object(forKey: Self.schemaKey) as? Int ?? 0
        if storedVersion == 0 {
            if defaults.object(forKey: Self.globalKey) == nil {
                let legacy = defaults.object(forKey: Self.legacyGlobalKey) as? Bool
                defaults.set(legacy ?? true, forKey: Self.globalKey)
            }
            defaults.set(Self.currentSchemaVersion, forKey: Self.schemaKey)
        }

        globalEnabled = defaults.object(forKey: Self.globalKey) as? Bool ?? true
        let rawOverrides = defaults.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:]
        chatOverrides = rawOverrides.reduce(into: [:]) { result, pair in
            guard !pair.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = AutomaticTranslationOverride(rawValue: pair.value),
                  value != .inherit else { return }
            result[pair.key] = value
        }
    }

    static func applicationStore() -> AutomaticTranslationSettingsStore {
        AutomaticTranslationSettingsStore(defaults: .standard)
    }

    func setGlobalEnabled(_ enabled: Bool) {
        globalEnabled = enabled
        defaults?.set(enabled, forKey: Self.globalKey)
    }

    func override(for chatID: String) -> AutomaticTranslationOverride {
        chatOverrides[chatID] ?? .inherit
    }

    func setOverride(_ value: AutomaticTranslationOverride, for chatID: String) {
        guard !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if value == .inherit {
            chatOverrides.removeValue(forKey: chatID)
        } else {
            chatOverrides[chatID] = value
        }
        persistOverrides()
    }

    func effectiveEnabled(for chatID: String) -> Bool {
        switch override(for: chatID) {
        case .inherit: globalEnabled
        case .enabled: true
        case .disabled: false
        }
    }

    private func persistOverrides() {
        let raw = chatOverrides.mapValues(\.rawValue)
        defaults?.set(raw, forKey: Self.overridesKey)
    }
}
