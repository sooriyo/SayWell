import Foundation

/// Debounced Singlish → English lookups for the keyboard suggestion bar.
@MainActor
final class TranslationSuggester {
    private let api = SayWellAPI.shared
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var lastRequested = ""
    private var memoryCache: [String: TranslationResponse] = [:]

    private let debounceNanoseconds: UInt64 = 700_000_000
    private let minChars = 2

    var onUpdate: ((SuggestionState) -> Void)?

    enum SuggestionState: Equatable {
        case idle
        case needsFullAccess
        case loading(phrase: String)
        case ready(phrase: String, translation: TranslationResponse)
        case failed(phrase: String, message: String)
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

    func schedule(phrase: String, hasFullAccess: Bool) {
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
            onUpdate?(.ready(phrase: trimmed, translation: cached))
            return
        }

        if let persisted = LocalPhraseCache.lookup(phrase: trimmed) {
            memoryCache[trimmed.lowercased()] = persisted
            LocalPhraseCache.record(phrase: trimmed, response: persisted)
            lastRequested = trimmed
            onUpdate?(.ready(phrase: trimmed, translation: persisted))
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
            onUpdate?(.ready(phrase: trimmed, translation: response))
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.fetch(phrase: trimmed)
        }
    }

    private func fetch(phrase: String) async {
        guard phrase != lastRequested || memoryCache[phrase.lowercased()] == nil else { return }

        requestTask?.cancel()
        onUpdate?(.loading(phrase: phrase))

        let task = Task {
            do {
                let result = try await api.translate(text: phrase)
                guard !Task.isCancelled else { return }
                memoryCache[phrase.lowercased()] = result
                if memoryCache.count > 64 {
                    memoryCache.removeAll(keepingCapacity: true)
                }
                LocalPhraseCache.record(phrase: phrase, response: result)
                lastRequested = phrase
                onUpdate?(.ready(phrase: phrase, translation: result))
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch let error as SayWellError {
                guard !Task.isCancelled else { return }
                onUpdate?(.failed(phrase: phrase, message: error.localizedDescription))
            } catch {
                guard !Task.isCancelled else { return }
                onUpdate?(
                    .failed(
                        phrase: phrase,
                        message: SayWellError.network(underlying: error).localizedDescription
                    )
                )
            }
        }

        requestTask = task
        await task.value
    }
}

enum KeyboardPhraseExtractor {
    /// Current Singlish phrase before the cursor — last sentence-ish segment.
    static func currentPhrase(beforeCursor context: String?) -> String {
        guard let context, !context.isEmpty else { return "" }

        let separators = CharacterSet(charactersIn: "\n.!?")
        let parts = context.components(separatedBy: separators)
        let last = parts.last ?? context
        return last.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
