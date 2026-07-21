import Foundation

/// Stable per-install id sent as `X-Device-Id` for Worker rate limiting.
/// Prefer the App Group suite so the host app and keyboard share one id.
enum DeviceIDStore {
    static let appGroupID = "group.dev.saywell.app"
    private static let key = "saywell.deviceId"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var deviceID: String {
        if let stored = defaults.string(forKey: key), !stored.isEmpty {
            return stored
        }

        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }
}
