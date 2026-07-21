import Foundation

/// Debounced Singlish → English lookups for the keyboard suggestion bar.
@MainActor
final class TranslationSuggester {
    private let api = SayWellAPI.shared
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var lastRequested = ""
    private var memoryCache: [String: TranslationResponse] = [:]

    private let debounceNanoseconds: UInt64 = 1_000_000_000  // 1 second — wait until user pauses
    private let minChars = 2

    var onUpdate: ((SuggestionState) -> Void)?

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
        onUpdate?(.idle)
    }

    func schedule(phraseData: KeyboardPhrase, hasFullAccess: Bool) {
        let phrase = phraseData.text
        let charCount = phraseData.characterCount
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

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

        if let cached = memoryCache[trimmed.lowercased()] {
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: cached))
            return
        }

        if let persisted = LocalPhraseCache.lookup(phrase: trimmed) {
            memoryCache[trimmed.lowercased()] = persisted
            LocalPhraseCache.record(phrase: trimmed, response: persisted)
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, charCount: charCount, translation: persisted))
            return
        }

        if let downloaded = CommonPhrasesStore.lookup(phrase: trimmed) {
            let response = TranslationResponse(
                translation: downloaded,
                source: .builtin,
                normalized: trimmed
            )
            memoryCache[trimmed.lowercased()] = response
            LocalPhraseCache.record(phrase: trimmed, response: response)
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
        guard phrase != lastRequested || memoryCache[phrase.lowercased()] == nil else { return }

        requestTask?.cancel()
        onUpdate?(.loading(phrase: phrase, charCount: charCount))

        let task = Task {
            do {
                let result = try await api.translate(text: phrase)
                guard !Task.isCancelled else { return }
                memoryCache[phrase.lowercased()] = result
                if memoryCache.count > 64 {
                    if let oldestKey = memoryCache.keys.first {
                        memoryCache.removeValue(forKey: oldestKey)
                    }
                }
                LocalPhraseCache.record(phrase: phrase, response: result)
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
