import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class TranslationViewModel {
    enum Phase: Equatable {
        case welcome
        case loading(phrase: String)
        case success
        case failure(String)
    }

    var inputText = ""
    var translation: TranslationResponse?
    var errorMessage: String?
    var isLoading = false
    var didCopy = false
    private(set) var recentHistory: [TranslationHistoryEntry] = []

    private let api: SayWellAPI
    private var translateTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init(api: SayWellAPI = .shared) {
        self.api = api
        reloadHistory()
    }

    var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var characterCount: Int { trimmedInput.count }

    var isOverLimit: Bool {
        characterCount > SayWellAPI.maxInputChars
    }

    var canTranslate: Bool {
        !trimmedInput.isEmpty && !isOverLimit && !isLoading
    }

    var phase: Phase {
        if isLoading { return .loading(phrase: trimmedInput) }
        if translation != nil { return .success }
        if let errorMessage { return .failure(errorMessage) }
        return .welcome
    }

    var scrollToken: String {
        switch phase {
        case .welcome: "welcome"
        case .loading: "loading"
        case .success: "success"
        case .failure: "failure"
        }
    }

    func translate() async {
        translateTask?.cancel()

        let text = trimmedInput
        guard !text.isEmpty else {
            errorMessage = SayWellError.emptyInput.localizedDescription
            translation = nil
            Haptics.notify(.warning)
            return
        }

        guard !isOverLimit else {
            errorMessage = SayWellError.inputTooLong.localizedDescription
            translation = nil
            Haptics.notify(.warning)
            return
        }

        // Check the personal phrase cache first — if we have it, skip the network entirely.
        if let cached = LocalPhraseCache.lookup(phrase: text) {
            translation = cached
            LocalPhraseCache.record(phrase: text, response: cached)
            TranslationHistoryStore.record(singlish: text, response: cached)
            reloadHistory()
            Haptics.notify(.success)
            return
        }

        // Check the downloaded common phrases (offline!) — if we have it, skip the network.
        if let downloaded = CommonPhrasesStore.lookup(phrase: text) {
            translation = TranslationResponse(
                translation: downloaded,
                source: .builtin,
                normalized: text
            )
            LocalPhraseCache.record(phrase: text, response: translation!)
            TranslationHistoryStore.record(singlish: text, response: translation!)
            reloadHistory()
            Haptics.notify(.success)
            return
        }

        isLoading = true
        errorMessage = nil
        translation = nil
        didCopy = false

        let task = Task {
            do {
                let result = try await api.translate(text: text)
                guard !Task.isCancelled else { return }
                translation = result
                LocalPhraseCache.record(phrase: text, response: result)
                TranslationHistoryStore.record(singlish: text, response: result)
                reloadHistory()
                Haptics.notify(.success)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch let error as SayWellError {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                Haptics.notify(.error)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = SayWellError.network(underlying: error).localizedDescription
                Haptics.notify(.error)
            }
        }

        translateTask = task
        await task.value
        if translateTask == task {
            isLoading = false
            translateTask = nil
        }
    }

    func retry() async {
        await translate()
    }

    func copyTranslation() {
        guard let translation else { return }
        UIPasteboard.general.string = translation.translation
        didCopy = true
        Haptics.impact(.light)

        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    func useExample(_ text: String) {
        translateTask?.cancel()
        isLoading = false
        inputText = text
        errorMessage = nil
        translation = nil
        didCopy = false
        Haptics.impact(.soft)
    }

    func useHistoryEntry(_ entry: TranslationHistoryEntry) {
        useExample(entry.singlish)
    }

    func clearHistory() {
        TranslationHistoryStore.clear()
        reloadHistory()
    }

    func clearLocalPhraseCache() {
        LocalPhraseCache.clear()
    }

    var cachedPhraseCount: Int {
        LocalPhraseCache.count
    }

    func reloadHistory() {
        recentHistory = TranslationHistoryStore.load()
    }

    func clear() {
        translateTask?.cancel()
        isLoading = false
        inputText = ""
        errorMessage = nil
        translation = nil
        didCopy = false
    }

    // MARK: - Common Phrases Management (Smart Syncing)

    /// Manually trigger a sync of common phrases from backend (ignores 24-hour throttle).
    func syncCommonPhrases() async -> Bool {
        return await CommonPhrasesStore.syncIfNeeded()
    }

    /// Clear downloaded common phrases cache.
    func clearCommonPhrases() {
        CommonPhrasesStore.clear()
    }

    /// Number of downloaded common phrases available offline.
    var commonPhrasesCount: Int {
        CommonPhrasesStore.phraseCount
    }

    /// Local version of downloaded common phrases.
    var commonPhrasesVersion: String? {
        CommonPhrasesStore.localVersion
    }

    /// When common phrases were last downloaded.
    var commonPhrasesLastDownloaded: Date? {
        CommonPhrasesStore.lastDownloadedAt
    }
}

// MARK: - Haptics

private enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
