import Foundation

/// A phrase-level cache entry stored in the App Group.
struct PhraseCacheEntry: Codable, Equatable {
    let phrase: String  // storage key: "{tone}:{normalized-or-raw}"
    var translation: TranslationResponse
    var hitCount: Int
    var lastUsedAt: Date
}

/// Personalized, frequency-ranked cache of the top ~100 phrases this user translates often.
/// Persisted to App Group UserDefaults so it survives keyboard extension purges and is shared
/// between the keyboard extension and host app.
enum LocalPhraseCache {
    private static let key = "saywell.localPhraseCache.v2"
    private static let maxEntries = 100

    private static var memoryEntries: [PhraseCacheEntry]?
    private static var isDirty = false

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: DeviceIDStore.appGroupID) ?? .standard
    }

    private static func storageKey(phrase: String, normalized: String, tone: TranslationTone) -> String {
        let base = normalized.isEmpty ? phrase.lowercased() : normalized.lowercased()
        return "\(tone.rawValue):\(base)"
    }

    private static func aliasKey(phrase: String, tone: TranslationTone) -> String {
        "\(tone.rawValue):\(phrase.lowercased())"
    }

    private static func ensureLoaded() {
        guard memoryEntries == nil else { return }
        memoryEntries = loadFromDisk()
    }

    private static func loadFromDisk() -> [PhraseCacheEntry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([PhraseCacheEntry].self, from: data)
        else { return [] }
        return entries
    }

    private static func saveToDisk(_ entries: [PhraseCacheEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
        isDirty = false
    }

    /// Look up a phrase in the persisted cache. Returns nil if not found.
    static func lookup(
        phrase: String,
        tone: TranslationTone = KeyboardStatusStore.snapshot.translationTone,
        normalized: String? = nil
    ) -> TranslationResponse? {
        ensureLoaded()
        guard let entries = memoryEntries else { return nil }

        let lowered = phrase.lowercased()
        let alias = aliasKey(phrase: phrase, tone: tone)
        let normalizedPhrase = (normalized ?? SinglishNormalizer.cacheKeyPhrase(for: phrase, tone: tone)).lowercased()
        let normalizedStorage = storageKey(phrase: normalizedPhrase, normalized: normalizedPhrase, tone: tone)

        if let hit = entries.first(where: { $0.phrase == alias }) {
            return hit.translation
        }

        if let hit = entries.first(where: { $0.phrase == normalizedStorage }) {
            return hit.translation
        }

        if let hit = entries.first(where: {
            $0.phrase.hasPrefix("\(tone.rawValue):")
                && $0.translation.normalized.lowercased() == lowered
        }) {
            return hit.translation
        }

        if normalizedPhrase != lowered,
           let hit = entries.first(where: {
               $0.phrase.hasPrefix("\(tone.rawValue):")
                   && $0.translation.normalized.lowercased() == normalizedPhrase
           }) {
            return hit.translation
        }

        return nil
    }

    /// Record a new or updated translation. Persists immediately when `writeThrough` is true.
    static func record(
        phrase: String,
        response: TranslationResponse,
        tone: TranslationTone = KeyboardStatusStore.translationTone,
        bumpHitCount: Bool = true,
        writeThrough: Bool = false
    ) {
        ensureLoaded()
        var entries = memoryEntries ?? []

        let primary = storageKey(phrase: phrase, normalized: response.normalized, tone: tone)
        let alias = aliasKey(phrase: phrase, tone: tone)

        func upsert(_ storageKey: String) {
            if let idx = entries.firstIndex(where: { $0.phrase == storageKey }) {
                if bumpHitCount {
                    entries[idx].hitCount += 1
                }
                entries[idx].lastUsedAt = Date()
                entries[idx].translation = response
            } else {
                entries.append(PhraseCacheEntry(
                    phrase: storageKey,
                    translation: response,
                    hitCount: 1,
                    lastUsedAt: Date()
                ))
            }
        }

        upsert(primary)
        if alias != primary {
            upsert(alias)
        }

        PhraseAliasStore.learn(typed: phrase, normalized: response.normalized, tone: tone)
        if !response.normalized.isEmpty {
            SinglishNormalizer.addVocabulary(from: [response.normalized])
        }

        if entries.count > maxEntries {
            if let evictIdx = entries.indices.min(by: { a, b in
                (entries[a].hitCount, entries[a].lastUsedAt) < (entries[b].hitCount, entries[b].lastUsedAt)
            }) {
                entries.remove(at: evictIdx)
            }
        }

        memoryEntries = entries
        isDirty = true
        if writeThrough {
            saveToDisk(entries)
        }
    }

    /// Write in-memory changes to disk (call when keyboard extension disappears).
    static func flush() {
        guard isDirty, let entries = memoryEntries else { return }
        saveToDisk(entries)
    }

    /// Number of entries currently in the cache.
    static var count: Int {
        ensureLoaded()
        return memoryEntries?.count ?? 0
    }

    /// Clear the entire cache.
    static func clear() {
        memoryEntries = []
        isDirty = false
        defaults.removeObject(forKey: key)
    }
}
