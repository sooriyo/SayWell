import SwiftUI

@main
struct SayWellApp: App {
    init() {
        // Seed shared device id so the keyboard inherits the same rate-limit key.
        _ = DeviceIDStore.deviceID
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
