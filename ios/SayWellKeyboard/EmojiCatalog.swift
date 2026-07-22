import Foundation

struct EmojiEntry: Decodable, Equatable {
    let c: String
    let k: [String]

    var character: String { c }
}

struct EmojiCategory: Decodable, Equatable {
    let id: String
    let name: String
    let icon: String
    let emojis: [EmojiEntry]

    var characters: [String] {
        emojis.map(\.c)
    }
}

enum EmojiCatalog {
    private static let recentID = "recent"
    private static let recentIcon = "clock"
    private static let maxRecents = 40

    private static let bundledCategories: [EmojiCategory] = {
        guard let url = Bundle.main.url(forResource: "emojis", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.categories
    }()

    /// Native keyboard groups Smileys + People into one "Smileys & People" section.
    private static let mergedCategories: [EmojiCategory] = {
        var cats = bundledCategories
        if let smileysIdx = cats.firstIndex(where: { $0.id == "smileys" }),
           let peopleIdx = cats.firstIndex(where: { $0.id == "people" }) {
            cats[smileysIdx] = EmojiCategory(
                id: "smileys",
                name: "Smileys & People",
                icon: "face.smiling",
                emojis: cats[smileysIdx].emojis + cats[peopleIdx].emojis
            )
            cats.remove(at: peopleIdx)
        }
        return cats
    }()

    /// Categories shown in the emoji keyboard: Frequently Used first (when non-empty),
    /// then the native 8 (Smileys & People merged).
    static var displayCategories: [EmojiCategory] {
        var cats = mergedCategories
        let recents = EmojiRecentStore.recents
        if !recents.isEmpty {
            cats.insert(
                EmojiCategory(
                    id: recentID,
                    name: "Frequently Used",
                    icon: recentIcon,
                    emojis: recents.map { EmojiEntry(c: $0, k: []) }
                ),
                at: 0
            )
        }
        return cats
    }

    private static var allEntries: [EmojiEntry] {
        bundledCategories.flatMap(\.emojis)
    }

    static var categories: [EmojiCategory] {
        let recentEntries = EmojiRecentStore.recents.map { EmojiEntry(c: $0, k: []) }
        let recentCategory = EmojiCategory(
            id: recentID,
            name: "Recent",
            icon: recentIcon,
            emojis: recentEntries
        )
        return [recentCategory] + bundledCategories
    }

    static func emojis(for categoryID: String) -> [String] {
        categories.first { $0.id == categoryID }?.characters ?? []
    }

    static func search(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var seen = Set<String>()
        var results: [String] = []

        for entry in allEntries {
            guard !seen.contains(entry.c) else { continue }
            let matches = entry.k.contains { keyword in
                keyword.contains(trimmed) || trimmed.contains(keyword)
            }
            if matches {
                seen.insert(entry.c)
                results.append(entry.c)
            }
        }
        return results
    }

    static func recordRecent(_ emoji: String) {
        EmojiRecentStore.record(emoji, limit: maxRecents)
    }

    private struct Payload: Decodable {
        let categories: [EmojiCategory]
    }
}

enum EmojiRecentStore {
    private static let key = "saywell.keyboard.emojiRecents"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.dev.saywell.app") ?? .standard
    }

    static var recents: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func record(_ emoji: String, limit: Int) {
        var list = recents.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        if list.count > limit {
            list = Array(list.prefix(limit))
        }
        defaults.set(list, forKey: key)
    }
}
