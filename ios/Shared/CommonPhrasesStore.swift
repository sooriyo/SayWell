import Foundation

/// Metadata about the common phrases (version + lastUpdated timestamp).
struct CommonPhrasesMetadata: Codable {
    let version: String
    let lastUpdated: Date
}

/// Full common phrases bundle: metadata + phrases dictionary + spelling variants.
struct CommonPhrasesBundle: Codable {
    let version: String
    let lastUpdated: Date
    let downloadedAt: Date
    let phrases: [String: String]
    let variants: [String: [String]]?

    init(
        version: String,
        lastUpdated: Date,
        downloadedAt: Date,
        phrases: [String: String],
        variants: [String: [String]]? = nil
    ) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.downloadedAt = downloadedAt
        self.phrases = phrases
        self.variants = variants
    }
}

/// Smart syncing store for common phrases downloaded from the backend.
/// Handles versioning, update detection, and local caching via App Group.
/// Syncs only when: (1) first time, (2) >24 hours since last check, (3) new version available.
enum CommonPhrasesStore {
    private static let appGroupID = DeviceIDStore.appGroupID
    private static let bundleKey = "saywell.commonPhrases.bundle"
    private static let metadataKey = "saywell.commonPhrases.metadata"
    private static let lastCheckKey = "saywell.commonPhrases.lastCheck"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    private static var urlSession: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }

    // MARK: - Local Storage

    private static var cachedPhrases: [String: String]?

    private static func ensurePhrasesLoaded() {
        guard cachedPhrases == nil else { return }
        if let bundle = loadLocal() {
            cachedPhrases = bundle.phrases
            applySyncedData(phrases: bundle.phrases, variants: bundle.variants)
        }
    }

    private static func invalidatePhraseCache() {
        cachedPhrases = nil
    }

    /// Load locally stored common phrases bundle (if any).
    static func loadLocal() -> CommonPhrasesBundle? {
        guard let data = defaults.data(forKey: bundleKey),
              let bundle = try? decoder.decode(CommonPhrasesBundle.self, from: data)
        else { return nil }
        return bundle
    }

    /// Save common phrases bundle to local storage.
    private static func saveLocal(_ bundle: CommonPhrasesBundle) {
        guard let data = try? encoder.encode(bundle) else { return }
        defaults.set(data, forKey: bundleKey)
        cachedPhrases = bundle.phrases
        applySyncedData(phrases: bundle.phrases, variants: bundle.variants)
    }

    private static func applySyncedData(phrases: [String: String], variants: [String: [String]]?) {
        if let variants {
            SinglishNormalizer.applyVariants(variants)
        }
        SinglishNormalizer.rebuildVocabulary(fromPhraseKeys: Array(phrases.keys))
    }

    // MARK: - Metadata & Versioning

    /// Load metadata of local copy (version + lastUpdated).
    static func loadLocalMetadata() -> CommonPhrasesMetadata? {
        guard let data = defaults.data(forKey: metadataKey),
              let metadata = try? decoder.decode(CommonPhrasesMetadata.self, from: data)
        else { return nil }
        return metadata
    }

    /// Save metadata locally.
    private static func saveLocalMetadata(_ metadata: CommonPhrasesMetadata) {
        guard let data = try? encoder.encode(metadata) else { return }
        defaults.set(data, forKey: metadataKey)
    }

    /// When we last checked the backend for updates.
    static var lastCheckTime: Date? {
        let timestamp = defaults.double(forKey: lastCheckKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Record that we checked the backend now.
    private static func recordCheckTime() {
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
    }

    /// Should we check the backend for updates?
    /// Returns true if: never checked, or more than 24 hours since last check.
    static var shouldCheckForUpdates: Bool {
        guard let lastCheck = lastCheckTime else { return true }
        return Date().timeIntervalSince(lastCheck) > 86_400 // 24 hours in seconds
    }

    // MARK: - Backend Sync

    /// Fetch version metadata from backend (lightweight: ~100 bytes).
    static func fetchRemoteMetadata() async throws -> CommonPhrasesMetadata {
        let url = URL(string: "https://saywell-backend.saywell.workers.dev/api/common-phrases/meta")!
        let (data, _) = try await urlSession.data(from: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(CommonPhrasesMetadata.self, from: data)
        return response
    }

    /// Fetch full common phrases bundle from backend (~10KB).
    static func fetchRemoteFull() async throws -> CommonPhrasesBundle {
        let url = URL(string: "https://saywell-backend.saywell.workers.dev/api/common-phrases/full")!
        let (data, _) = try await urlSession.data(from: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(CommonPhrasesBundle.self, from: data)
        return bundle
    }

    /// Smart sync: check if backend has newer version, download if so.
    /// Returns true if updated, false if already up-to-date.
    /// Syncs at most once per 24 hours (throttled).
    static func syncIfNeeded() async -> Bool {
        // Throttle: only check once per 24 hours
        guard shouldCheckForUpdates else { return false }

        defer { recordCheckTime() }

        do {
            // 1. Lightweight version check
            let remoteMetadata = try await fetchRemoteMetadata()
            let localMetadata = loadLocalMetadata()

            // 2. Compare versions
            if let local = localMetadata, local.version == remoteMetadata.version {
                // Already up-to-date
                return false
            }

            // 3. Newer version available, download full bundle
            let remoteBundle = try await fetchRemoteFull()
            saveLocal(remoteBundle)
            saveLocalMetadata(remoteMetadata)

            return true // Updated
        } catch {
            // Silently fail — we'll use cached copy if available
            print("[CommonPhrasesStore] Sync failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Lookup

    /// Lookup a phrase in the locally-stored common phrases.
    static func lookup(phrase: String) -> String? {
        ensurePhrasesLoaded()
        let normalized = SinglishNormalizer.normalize(phrase)
        // Strip trailing punctuation (? ! .) that normalize() appends as separate tokens
        // so "bath kawa da ?" matches the stored phrase "bath kawa da"
        let cleaned = normalized
            .replacingOccurrences(of: #"\s+[.!?]+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let key = cleaned.isEmpty ? normalized : cleaned
        return cachedPhrases?[key]
    }

    // MARK: - Management

    /// Clear all downloaded common phrases (for testing or user reset).
    static func clear() {
        defaults.removeObject(forKey: bundleKey)
        defaults.removeObject(forKey: metadataKey)
        defaults.removeObject(forKey: lastCheckKey)
        invalidatePhraseCache()
    }

    /// Size of locally-stored bundle in bytes (for diagnostics).
    static var sizeBytes: Int {
        guard let data = defaults.data(forKey: bundleKey) else { return 0 }
        return data.count
    }

    /// Count of locally-stored phrases.
    static var phraseCount: Int {
        ensurePhrasesLoaded()
        return cachedPhrases?.count ?? 0
    }

    /// Local version string (for UI display).
    static var localVersion: String? {
        loadLocalMetadata()?.version
    }

    /// Human-readable "last downloaded" time.
    static var lastDownloadedAt: Date? {
        loadLocal()?.downloadedAt
    }
}
