import Foundation

/// Debounced Singlish → English lookups for the keyboard suggestion bar.
@MainActor
final class TranslationSuggester {
    private let api = SayWellAPI.shared
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var lastRequested = ""
    private var memoryCache: [String: TranslationResponse] = [:]
    private var skipNextLoadingState = false

    private let debounceNanoseconds: UInt64 = 1_000_000_000  // 1 second — wait until user pauses
    private let minChars = 2

    var onUpdate: ((SuggestionState) -> Void)?

    private func cacheKey(phrase: String, tone: TranslationTone) -> String {
        "\(tone.rawValue):\(phrase.lowercased())"
    }

    private var currentTone: TranslationTone {
        KeyboardStatusStore.translationTone
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
        let phrase = phraseData.text
        let charCount = phraseData.characterCount
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

        guard KeyboardStatusStore.translationsEnabled else {
            cancel()
            lastRequested = ""
            onUpdate?(.idle)
            return
        }

        guard hasFullAccess else {
            cancel()
            onUpdate?(.needsFullAccess)
            return
        }

        guard trimmed.count >= minChars else {
            cancel()
            lastRequested = ""
            onUpdate?(.idle)
            return
        }

        guard !GibberishDetection.isLikelyGibberish(trimmed) else {
            cancel()
            lastRequested = ""
            onUpdate?(.idle)
            return
        }

        let tone = currentTone
        let cacheLookupKey = cacheKey(phrase: trimmed, tone: tone)

        if let cached = memoryCache[cacheLookupKey] {
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: cached))
            return
        }

        if let persisted = LocalPhraseCache.lookup(phrase: trimmed, tone: tone) {
            let withSource = TranslationResponse(
                translation: persisted.translation,
                source: .persistedCache,
                normalized: persisted.normalized
            )
            memoryCache[cacheLookupKey] = withSource
            LocalPhraseCache.record(phrase: trimmed, response: withSource, tone: tone)
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: withSource))
            return
        }

        if tone == .casual, let downloaded = CommonPhrasesStore.lookup(phrase: trimmed) {
            let response = TranslationResponse(
                translation: downloaded,
                source: .commonPhrases,
                normalized: trimmed
            )
            memoryCache[cacheLookupKey] = response
            LocalPhraseCache.record(phrase: trimmed, response: response, tone: tone)
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: response))
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.fetch(phrase: trimmed, charCount: charCount)
        }
    }

    private func fetch(phrase: String, charCount: Int) async {
        let tone = currentTone
        let cacheLookupKey = cacheKey(phrase: phrase, tone: tone)
        guard phrase != lastRequested || memoryCache[cacheLookupKey] == nil else { return }

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
                memoryCache[cacheLookupKey] = result
                if memoryCache.count > 64 {
                    if let oldestKey = memoryCache.keys.first {
                        memoryCache.removeValue(forKey: oldestKey)
                    }
                }
                LocalPhraseCache.record(phrase: phrase, response: result, tone: tone)
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
