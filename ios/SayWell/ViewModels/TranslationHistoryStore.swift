import Foundation

struct TranslationHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let singlish: String
    let english: String
    let normalized: String
    let source: TranslationSource
    let createdAt: Date

    init(
        id: UUID = UUID(),
        singlish: String,
        english: String,
        normalized: String,
        source: TranslationSource,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.singlish = singlish
        self.english = english
        self.normalized = normalized
        self.source = source
        self.createdAt = createdAt
    }
}

enum TranslationHistoryStore {
    private static let key = "saywell.translationHistory"
    private static let maxEntries = 8

    static func load() -> [TranslationHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([TranslationHistoryEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func save(_ entries: [TranslationHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func record(singlish: String, response: TranslationResponse) {
        let trimmed = singlish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var entries = load()
        entries.removeAll { $0.singlish.lowercased() == trimmed.lowercased() }

        let entry = TranslationHistoryEntry(
            singlish: trimmed,
            english: response.translation,
            normalized: response.normalized,
            source: response.source
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
