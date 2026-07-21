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
        let touchTrap = UIColor.white.withAlphaComponent(0.01)
        inputView?.backgroundColor = touchTrap
        inputView?.isOpaque = false
        inputView?.clipsToBounds = false

        setupKeyboard()
        bindSuggester()
        refreshSuggestion()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        KeyboardStatusStore.recordKeyboardActive(hasFullAccess: hasFullAccess)
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
        print("🎹 [SETUP] Setting up keyboard")
        let touchTrap = UIColor.white.withAlphaComponent(0.01)
        view.backgroundColor = touchTrap
        view.isOpaque = false
        view.clipsToBounds = false

        let keyboard = SayWellKeyboardView(frame: .zero)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.delegate = self
        view.addSubview(keyboard)
        keyboardView = keyboard
        print("🎹 [SETUP] Keyboard view added: \(type(of: keyboard))")

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
        let phraseData = KeyboardPhraseExtractor.currentPhrase(
            beforeCursor: textDocumentProxy.documentContextBeforeInput
        )
        suggester.schedule(phraseData: phraseData, hasFullAccess: hasFullAccess)
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

    private func insertTranslation(_ english: String, replacingPhrase phrase: String, charCount: Int) {
        guard !english.isEmpty else { return }

        if charCount > 0 {
            for _ in 0..<charCount {
                textDocumentProxy.deleteBackward()
            }
        }

        // Add space before translation if there's existing text and it doesn't end with whitespace
        let beforeCursor = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !beforeCursor.isEmpty
            && !beforeCursor.hasSuffix(" ")
            && !beforeCursor.hasSuffix("\n")
            && !beforeCursor.hasSuffix("\t")

        if needsSpace {
            textDocumentProxy.insertText(" ")
        }

        textDocumentProxy.insertText(english)
        suggester.reset()
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
        case .symbolsToggle:
            view.toggleSymbols()
        case .globe:
            advanceToNextInputMode()
        case .emoji:
            advanceToNextInputMode()
        case .acceptSuggestion:
            if case let .ready(phrase, charCount, translation) = view.currentSuggestion {
                insertTranslation(translation.translation, replacingPhrase: phrase, charCount: charCount)
            }
        }
    }
}
