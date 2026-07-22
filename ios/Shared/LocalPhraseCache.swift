import Foundation

/// A phrase-level cache entry stored in the App Group.
struct PhraseCacheEntry: Codable, Equatable {
    let phrase: String  // lowercased, used as the cache key
    var translation: TranslationResponse
    var hitCount: Int
    var lastUsedAt: Date
}

/// Personalized, frequency-ranked cache of the top ~100 phrases this user translates often.
/// Persisted to App Group UserDefaults so it survives keyboard extension purges and is shared
/// between the keyboard extension and host app. Hit-count based: incrementing every time a
/// phrase is successfully served (network or cached), and evicting the lowest-count entry
/// when the table exceeds 100 entries.
enum LocalPhraseCache {
    private static let key = "saywell.localPhraseCache.v2"
    private static let maxEntries = 100

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: DeviceIDStore.appGroupID) ?? .standard
    }

    private static func cacheKey(phrase: String, tone: TranslationTone) -> String {
        "\(tone.rawValue):\(phrase.lowercased())"
    }

    static func load() -> [PhraseCacheEntry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([PhraseCacheEntry].self, from: data)
        else { return [] }
        return entries
    }

    private static func save(_ entries: [PhraseCacheEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    /// Look up a phrase in the persisted cache. Returns nil if not found.
    static func lookup(phrase: String, tone: TranslationTone = KeyboardStatusStore.translationTone) -> TranslationResponse? {
        let key = cacheKey(phrase: phrase, tone: tone)
        return load().first { $0.phrase == key }?.translation
    }

    /// Record a successful translation (network-sourced or cache-served). Increments hit count,
    /// updates lastUsedAt, and evicts the lowest-frequency entry if the cache exceeds 100 entries.
    static func record(
        phrase: String,
        response: TranslationResponse,
        tone: TranslationTone = KeyboardStatusStore.translationTone
    ) {
        let key = cacheKey(phrase: phrase, tone: tone)
        var entries = load()

        if let idx = entries.firstIndex(where: { $0.phrase == key }) {
            entries[idx].hitCount += 1
            entries[idx].lastUsedAt = Date()
            entries[idx].translation = response
        } else {
            entries.append(PhraseCacheEntry(
                phrase: key,
                translation: response,
                hitCount: 1,
                lastUsedAt: Date()
            ))
        }

        if entries.count > maxEntries {
            // Evict the entry with the lowest hitCount; break ties by oldest lastUsedAt.
            if let evictIdx = entries.indices.min(by: { a, b in
                (entries[a].hitCount, entries[a].lastUsedAt) < (entries[b].hitCount, entries[b].lastUsedAt)
            }) {
                entries.remove(at: evictIdx)
            }
        }

        save(entries)
    }

    /// Number of entries currently in the cache.
    static var count: Int {
        load().count
    }

    /// Clear the entire cache.
    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
