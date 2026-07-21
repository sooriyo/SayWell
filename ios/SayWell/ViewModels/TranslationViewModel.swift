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

    private let api: SayWellAPI
    private var translateTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init(api: SayWellAPI = .shared) {
        self.api = api
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

        isLoading = true
        errorMessage = nil
        translation = nil
        didCopy = false

        let task = Task {
            do {
                let result = try await api.translate(text: text)
                guard !Task.isCancelled else { return }
                translation = result
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

    func clear() {
        translateTask?.cancel()
        isLoading = false
        inputText = ""
        errorMessage = nil
        translation = nil
        didCopy = false
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
