import UIKit

final class KeyboardViewController: UIInputViewController {
    private let suggester = TranslationSuggester()
    private var keyboardView: SayWellKeyboardView!
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Let Auto Layout own the keyboard height so we don't leave a tall empty
        // gray band covering the host app (the circled overlay).
        inputView?.allowsSelfSizing = true
        // Kill any system-provided opaque fill so only our clear glass shows.
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false

        setupKeyboard()
        bindSuggester()
        refreshSuggestion()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardView.setNeedsInputModeSwitchKey(needsInputModeSwitchKey)
        updateHeight()
        refreshSuggestion()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshSuggestion()
        updateReturnKey()
    }

    private func setupKeyboard() {
        // Fully transparent — system provides the keyboard chrome/blur.
        view.backgroundColor = .clear
        view.isOpaque = false

        let keyboard = SayWellKeyboardView(frame: .zero)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.delegate = self
        view.addSubview(keyboard)
        keyboardView = keyboard

        // Priority < required so the system can still negotiate with the host.
        let height = view.heightAnchor.constraint(equalToConstant: SayWellKeyboardView.preferredHeight)
        height.priority = UILayoutPriority(999)
        heightConstraint = height

        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])

        keyboardView.setNeedsInputModeSwitchKey(needsInputModeSwitchKey)
        updateReturnKey()
        updateHeight()
    }

    private func updateHeight() {
        let next = SayWellKeyboardView.preferredHeight
        guard heightConstraint?.constant != next else { return }
        heightConstraint?.constant = next
        view.setNeedsLayout()
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
