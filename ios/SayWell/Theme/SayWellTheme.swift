import SwiftUI

enum SayWellTheme {
    static let brand = Color("AccentTeal")
    static let ink = Color(red: 0.07, green: 0.14, blue: 0.16)
    static let mist = Color(red: 0.93, green: 0.97, blue: 0.96)
    static let foam = Color(red: 0.98, green: 0.99, blue: 0.99)
    static let lagoon = Color(red: 0.12, green: 0.42, blue: 0.48)
    static let coral = Color(red: 0.86, green: 0.38, blue: 0.32)

    static var canvas: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.90, green: 0.96, blue: 0.95),
                Color(red: 0.96, green: 0.98, blue: 0.97),
                Color(red: 0.88, green: 0.94, blue: 0.96),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var brandMark: Font {
        .system(.largeTitle, design: .serif).weight(.bold)
    }

    static var display: Font {
        .system(.title2, design: .serif).weight(.semibold)
    }

    static var body: Font {
        .system(.body, design: .rounded)
    }
}
