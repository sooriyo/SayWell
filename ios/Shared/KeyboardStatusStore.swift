import Foundation

/// Shared keyboard setup heartbeat between the extension and host app (App Group).
struct KeyboardSettingsSnapshot: Equatable {
    let translationsEnabled: Bool
    let translationTone: TranslationTone
}

enum KeyboardStatusStore {
    private static let lastActiveKey = "saywell.keyboard.lastActive"
    private static let hasFullAccessKey = "saywell.keyboard.hasFullAccess"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: DeviceIDStore.appGroupID) ?? .standard
    }

    /// Last time the keyboard extension appeared (any access level).
    static var lastActiveAt: Date? {
        let timestamp = defaults.double(forKey: lastActiveKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Whether the keyboard last reported Full Access (required for network translate).
    static var hasFullAccess: Bool {
        defaults.bool(forKey: hasFullAccessKey)
    }

    /// Keyboard has been used at least once with Full Access enabled.
    static var isReady: Bool {
        hasFullAccess && lastActiveAt != nil
    }

    private static let translationsEnabledKey = "saywell.keyboard.translationsEnabled"

    /// When false, the keyboard types normally without fetching translations.
    static var translationsEnabled: Bool {
        get {
            if defaults.object(forKey: translationsEnabledKey) == nil {
                return true
            }
            return defaults.bool(forKey: translationsEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: translationsEnabledKey)
        }
    }

    private static let translationToneKey = "saywell.keyboard.translationTone"

    /// How English translations should sound (shared with host app).
    static var translationTone: TranslationTone {
        get {
            guard let raw = defaults.string(forKey: translationToneKey),
                  let tone = TranslationTone(rawValue: raw) else {
                return .casual
            }
            return tone
        }
        set {
            defaults.set(newValue.rawValue, forKey: translationToneKey)
        }
    }

    /// Snapshot of keyboard settings — read once per suggestion refresh.
    static var snapshot: KeyboardSettingsSnapshot {
        KeyboardSettingsSnapshot(
            translationsEnabled: translationsEnabled,
            translationTone: translationTone
        )
    }

    /// Called by `SayWellKeyboard` when the extension becomes visible.
    static func recordKeyboardActive(hasFullAccess: Bool) {
        defaults.set(Date().timeIntervalSince1970, forKey: lastActiveKey)
        defaults.set(hasFullAccess, forKey: hasFullAccessKey)
    }
}
