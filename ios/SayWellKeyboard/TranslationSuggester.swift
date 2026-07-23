import Foundation

/// Debounced Singlish → English lookups for the keyboard suggestion bar.
@MainActor
final class TranslationSuggester {
    private let api = SayWellAPI.keyboard
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var lastRequested = ""
    private var memoryCache: [String: TranslationResponse] = [:]
    private var memoryCacheOrder: [String] = []
    private var skipNextLoadingState = false

    private let debounceNanoseconds: UInt64 = 1_000_000_000  // 1 second — wait until user pauses
    private let minChars = 2
    private let memoryCacheLimit = 64

    var onUpdate: ((SuggestionState) -> Void)?

    private func cacheKey(phrase: String, tone: TranslationTone) -> String {
        "\(tone.rawValue):\(phrase.lowercased())"
    }

    enum SuggestionState: Equatable {
        case idle
        case needsFullAccess
        case loading(phrase: String, charCount: Int)
        case ready(phrase: String, charCount: Int, translation: TranslationResponse)
        case failed(phrase: String, charCount: Int, message: String)
    }

    func cancel() {
        debounceTask?.cancel()
        requestTask?.cancel()
        debounceTask = nil
        requestTask = nil
    }

    /// Stop waiting for a pause; does not cancel an in-flight API request.
    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    func reset() {
        cancel()
        lastRequested = ""
        skipNextLoadingState = false
        onUpdate?(.idle)
    }

    /// Tone changed — allow re-fetch without flashing idle/loading in the suggestion bar.
    func prepareForToneChange() {
        cancel()
        lastRequested = ""
        skipNextLoadingState = true
    }

    func schedule(phraseData: KeyboardPhrase, hasFullAccess: Bool) {
        let settings = KeyboardStatusStore.snapshot
        let phrase = phraseData.text
        let charCount = phraseData.characterCount
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

        guard settings.translationsEnabled else {
            cancel()
            lastRequested = ""
            onUpdate?(.idle)
            return
        }

        guard hasFullAccess else {
            cancelDebounce()
            onUpdate?(.needsFullAccess)
            return
        }

        guard trimmed.count >= minChars else {
            cancelDebounce()
            if trimmed.isEmpty {
                requestTask?.cancel()
                lastRequested = ""
                onUpdate?(.idle)
            }
            return
        }

        guard !GibberishDetection.isLikelyGibberish(trimmed) else {
            cancelDebounce()
            requestTask?.cancel()
            lastRequested = ""
            onUpdate?(.idle)
            return
        }

        let tone = settings.translationTone
        let lookupPhrase = SinglishNormalizer.cacheKeyPhrase(for: trimmed, tone: tone)

        if let cached = memoryLookup(typed: trimmed, lookupPhrase: lookupPhrase, tone: tone) {
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: cached))
            return
        }

        if let persisted = LocalPhraseCache.lookup(phrase: trimmed, tone: tone, normalized: lookupPhrase) {
            let withSource = TranslationResponse(
                translation: persisted.translation,
                source: .persistedCache,
                normalized: persisted.normalized
            )
            rememberHit(typed: trimmed, response: withSource, tone: tone)
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: withSource))
            return
        }

        if tone == .casual, let downloaded = CommonPhrasesStore.lookup(phrase: lookupPhrase) {
            let response = TranslationResponse(
                translation: downloaded,
                source: .commonPhrases,
                normalized: lookupPhrase
            )
            rememberHit(typed: trimmed, response: response, tone: tone)
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: response))
            return
        }

        debounceTask?.cancel()
        let phraseSnapshot = trimmed
        let lookupSnapshot = lookupPhrase
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.fetch(
                phrase: phraseSnapshot,
                lookupPhrase: lookupSnapshot,
                charCount: charCount,
                tone: tone
            )
        }
    }

    private func rememberHit(typed: String, response: TranslationResponse, tone: TranslationTone) {
        storeInMemory(typed: typed, lookupPhrase: response.normalized.isEmpty
            ? SinglishNormalizer.cacheKeyPhrase(for: typed, tone: tone)
            : response.normalized,
            response: response,
            tone: tone)
        PhraseAliasStore.learn(typed: typed, normalized: response.normalized, tone: tone)
        SinglishNormalizer.addVocabulary(from: [response.normalized])
    }

    private func memoryLookup(typed: String, lookupPhrase: String, tone: TranslationTone) -> TranslationResponse? {
        if let hit = memoryCache[cacheKey(phrase: typed, tone: tone)] {
            touchMemoryKey(cacheKey(phrase: typed, tone: tone))
            return hit
        }

        if lookupPhrase.lowercased() != typed.lowercased(),
           let hit = memoryCache[cacheKey(phrase: lookupPhrase, tone: tone)] {
            touchMemoryKey(cacheKey(phrase: lookupPhrase, tone: tone))
            return hit
        }

        let lowered = typed.lowercased()
        for (key, value) in memoryCache where key.hasPrefix("\(tone.rawValue):") {
            if value.normalized.lowercased() == lowered || value.normalized.lowercased() == lookupPhrase.lowercased() {
                touchMemoryKey(key)
                return value
            }
        }
        return nil
    }

    private func storeInMemory(typed: String, lookupPhrase: String, response: TranslationResponse, tone: TranslationTone) {
        memoryStore(key: cacheKey(phrase: typed, tone: tone), response: response)
        let normalizedKey = cacheKey(phrase: lookupPhrase, tone: tone)
        if normalizedKey != cacheKey(phrase: typed, tone: tone) {
            memoryStore(key: normalizedKey, response: response)
        }
        if !response.normalized.isEmpty {
            let apiNormalizedKey = cacheKey(phrase: response.normalized, tone: tone)
            if apiNormalizedKey != normalizedKey && apiNormalizedKey != cacheKey(phrase: typed, tone: tone) {
                memoryStore(key: apiNormalizedKey, response: response)
            }
        }
    }

    private func memoryStore(key: String, response: TranslationResponse) {
        memoryCache[key] = response
        touchMemoryKey(key)
        while memoryCache.count > memoryCacheLimit, let oldest = memoryCacheOrder.first {
            memoryCacheOrder.removeFirst()
            memoryCache.removeValue(forKey: oldest)
        }
    }

    private func touchMemoryKey(_ key: String) {
        memoryCacheOrder.removeAll { $0 == key }
        memoryCacheOrder.append(key)
    }

    private func fetch(phrase: String, lookupPhrase: String, charCount: Int, tone: TranslationTone) async {
        if let cached = memoryLookup(typed: phrase, lookupPhrase: lookupPhrase, tone: tone) {
            skipNextLoadingState = false
            lastRequested = phrase
            onUpdate?(.ready(phrase: phrase, charCount: charCount, translation: cached))
            return
        }

        requestTask?.cancel()
        let showLoading = !skipNextLoadingState
        skipNextLoadingState = false
        if showLoading {
            onUpdate?(.loading(phrase: phrase, charCount: charCount))
        }

        let task = Task {
            do {
                let result = try await api.translate(text: phrase, tone: tone)
                guard !Task.isCancelled else { return }
                rememberHit(typed: phrase, response: result, tone: tone)
                LocalPhraseCache.record(phrase: phrase, response: result, tone: tone, writeThrough: false)
                lastRequested = phrase
                onUpdate?(.ready(phrase: phrase, charCount: charCount, translation: result))
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch let error as SayWellError {
                guard !Task.isCancelled else { return }
                onUpdate?(.failed(phrase: phrase, charCount: charCount, message: error.localizedDescription))
            } catch {
                guard !Task.isCancelled else { return }
                onUpdate?(
                    .failed(
                        phrase: phrase,
                        charCount: charCount,
                        message: SayWellError.network(underlying: error).localizedDescription
                    )
                )
            }
        }

        requestTask = task
        await task.value
    }
}

struct KeyboardPhrase {
    let text: String
    let characterCount: Int
}

enum KeyboardPhraseExtractor {
    /// Current Singlish phrase before the cursor — last sentence-ish segment.
    /// Returns both the trimmed phrase for lookup and the actual character count to delete.
    static func currentPhrase(beforeCursor context: String?) -> KeyboardPhrase {
        guard let context, !context.isEmpty else { return KeyboardPhrase(text: "", characterCount: 0) }

        // Find the last sentence-ending character (., !, ?, newline)
        let separators = CharacterSet(charactersIn: "\n.!?")
        let parts = context.components(separatedBy: separators)

        // Track the raw segment (before trimming) to calculate deletion count
        var rawSegment = parts.last ?? context
        var trimmed = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)

        // If we got empty string and there are multiple parts, try the second-to-last
        // (handles case where sentence ends with punctuation: "oyata kohomada?" → "oyata kohomada")
        if trimmed.isEmpty, parts.count > 1 {
            rawSegment = parts[parts.count - 2]
            trimmed = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return KeyboardPhrase(text: trimmed, characterCount: rawSegment.count)
    }
}
