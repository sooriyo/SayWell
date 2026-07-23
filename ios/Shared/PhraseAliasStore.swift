import Foundation

/// Learns `typed → normalized` mappings per user so repeat shorthand skips the API.
enum PhraseAliasStore {
    private static let key = "saywell.phraseAliases.v1"
    private static let maxEntries = 200

    private struct Entry: Codable {
        let storageKey: String
        var normalized: String
        var lastUsedAt: Date
    }

    private static var memoryEntries: [Entry]?
    private static var isDirty = false

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: DeviceIDStore.appGroupID) ?? .standard
    }

    private static func aliasKey(typed: String, tone: TranslationTone) -> String {
        "\(tone.rawValue):\(typed.lowercased())"
    }

    private static func ensureLoaded() {
        guard memoryEntries == nil else { return }
        memoryEntries = loadFromDisk()
    }

    private static func loadFromDisk() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    private static func saveToDisk(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
        isDirty = false
    }

    /// Returns the canonical normalized form for a typed phrase, if previously learned.
    static func lookup(typed: String, tone: TranslationTone) -> String? {
        ensureLoaded()
        let key = aliasKey(typed: typed, tone: tone)
        return memoryEntries?.first(where: { $0.storageKey == key })?.normalized
    }

    /// Remember that `typed` folds to `normalized` for future cache lookups.
    static func learn(typed: String, normalized: String, tone: TranslationTone) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let norm = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !norm.isEmpty else { return }
        guard trimmed.lowercased() != norm.lowercased() else { return }

        ensureLoaded()
        var entries = memoryEntries ?? []
        let storageKey = aliasKey(typed: trimmed, tone: tone)

        if let idx = entries.firstIndex(where: { $0.storageKey == storageKey }) {
            entries[idx].normalized = norm
            entries[idx].lastUsedAt = Date()
        } else {
            entries.append(Entry(storageKey: storageKey, normalized: norm, lastUsedAt: Date()))
        }

        if entries.count > maxEntries {
            if let evictIdx = entries.indices.min(by: { entries[$0].lastUsedAt < entries[$1].lastUsedAt }) {
                entries.remove(at: evictIdx)
            }
        }

        memoryEntries = entries
        isDirty = true
    }

    static func flush() {
        guard isDirty, let entries = memoryEntries else { return }
        saveToDisk(entries)
    }

    static func clear() {
        memoryEntries = []
        isDirty = false
        defaults.removeObject(forKey: key)
    }
}
