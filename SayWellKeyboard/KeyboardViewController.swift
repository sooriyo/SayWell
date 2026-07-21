import UIKit

final class KeyboardViewController: UIInputViewController {
    private let suggester = TranslationSuggester()
    private var keyboardView: SayWellKeyboardView!
    private var heightConstraint: NSLayoutConstraint?

    /// Matches stock iOS keyboard + compact predictive strip.
    private let keyboardHeight: CGFloat = 260

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard()
        bindSuggester()
        refreshSuggestion()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSuggestion()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshSuggestion()
        updateReturnKey()
    }

    private func setupKeyboard() {
        let keyboard = SayWellKeyboardView(frame: .zero)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.delegate = self
        view.addSubview(keyboard)
        keyboardView = keyboard

        let height = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        height.priority = .defaultHigh
        heightConstraint = height

        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])

        updateReturnKey()
    }

    private func bindSuggester() {
        suggester.onUpdate = { [weak self] state in
            self?.keyboardView.apply(suggestion: state)
        }
    }

    private func refreshSuggestion() {
        let phrase = KeyboardPhraseExtractor.currentPhrase(
            beforeCursor: textDocumentProxy.documentContextBeforeInput
        )
        suggester.schedule(phrase: phrase, hasFullAccess: hasFullAccess)
    }

    private func updateReturnKey() {
        let returnKeyType = textDocumentProxy.returnKeyType ?? .default
        keyboardView.setReturnKeyTitle(Self.title(for: returnKeyType))
    }

    private static func title(for type: UIReturnKeyType) -> String {
        switch type {
        case .go: return "go"
        case .google: return "search"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .search: return "search"
        case .send: return "send"
        case .done: return "done"
        case .continue: return "continue"
        default: return "return"
        }
    }

    private func insertTranslation(_ english: String, replacing phrase: String) {
        guard !english.isEmpty else { return }

        // Prefer deleting the tracked phrase; fall back to deleting by UTF-16 length.
        if !phrase.isEmpty {
            for _ in phrase {
                textDocumentProxy.deleteBackward()
            }
        }
        textDocumentProxy.insertText(english)
        suggester.reset()
        refreshSuggestion()
    }
}

extension KeyboardViewController: SayWellKeyboardViewDelegate {
    func keyboardView(_ view: SayWellKeyboardView, didTapKey key: KeyboardKey) {
        switch key {
        case .character(let value):
            textDocumentProxy.insertText(value)
            refreshSuggestion()
        case .space:
            textDocumentProxy.insertText(" ")
            refreshSuggestion()
        case .returnKey:
            textDocumentProxy.insertText("\n")
            suggester.reset()
            refreshSuggestion()
        case .backspace:
            textDocumentProxy.deleteBackward()
            refreshSuggestion()
        case .shift:
            view.toggleShift()
        case .layoutToggle:
            view.toggleLayout()
        case .globe:
            advanceToNextInputMode()
        case .acceptSuggestion:
            if case let .ready(phrase, translation) = view.currentSuggestion {
                insertTranslation(translation.translation, replacing: phrase)
            }
        }
    }
}
