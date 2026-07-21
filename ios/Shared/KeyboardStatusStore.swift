import Foundation

/// Shared keyboard setup heartbeat between the extension and host app (App Group).
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

    /// Called by `SayWellKeyboard` when the extension becomes visible.
    static func recordKeyboardActive(hasFullAccess: Bool) {
        defaults.set(Date().timeIntervalSince1970, forKey: lastActiveKey)
        defaults.set(hasFullAccess, forKey: hasFullAccessKey)
    }
}
