import UIKit

final class KeyboardViewController: UIInputViewController {
    private let suggester = TranslationSuggester()
    private var keyboardView: SayWellKeyboardView?
    private var heightConstraint: NSLayoutConstraint?
    private var toneHintTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Let Auto Layout own the keyboard height so we don't leave a tall empty
        // gray band covering the host app (the circled overlay).
        inputView?.allowsSelfSizing = true
        // Let the system keyboard tray show through — matches globe/mic bar seamlessly.
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false
        inputView?.clipsToBounds = false

        setupKeyboard()
        bindSuggester()
        refreshSuggestion()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toneHintTask?.cancel()
        toneHintTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        suggester.cancel()
        LocalPhraseCache.flush()
        PhraseAliasStore.flush()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        KeyboardStatusStore.recordKeyboardActive(hasFullAccess: hasFullAccess)
        keyboardView?.setNeedsInputModeSwitchKey(needsInputModeSwitchKey)
        keyboardView?.syncSuggestionBarToggle()
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
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = false

        let keyboard = SayWellKeyboardView(frame: .zero)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.delegate = self
        keyboard.onPreferredHeightChange = { [weak self] in
            self?.updateHeight()
        }
        view.addSubview(keyboard)
        keyboardView = keyboard

        // Priority < required so the system can still negotiate with the host.
        let height = view.heightAnchor.constraint(equalToConstant: SayWellKeyboardView.preferredHeight)
        height.priority = UILayoutPriority(999)
        heightConstraint = height

        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])

        keyboardView?.setNeedsInputModeSwitchKey(needsInputModeSwitchKey)
        updateReturnKey()
        updateHeight()
    }

    private func updateHeight() {
        let next = keyboardView?.preferredContentHeight ?? SayWellKeyboardView.preferredHeight
        guard heightConstraint?.constant != next else { return }
        heightConstraint?.constant = next
        view.setNeedsLayout()
    }

    private func bindSuggester() {
        suggester.onUpdate = { [weak self] state in
            self?.keyboardView?.apply(suggestion: state)
        }
    }

    /// Coalesce refreshes so `documentContextBeforeInput` is committed after `insertText`.
    private var refreshTask: Task<Void, Never>?

    private func refreshSuggestion() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            // One run-loop turn — avoids reading stale proxy text on the same call stack as insertText.
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard !Task.isCancelled, let self else { return }
            let phraseData = KeyboardPhraseExtractor.currentPhrase(
                beforeCursor: self.textDocumentProxy.documentContextBeforeInput
            )
            self.suggester.schedule(phraseData: phraseData, hasFullAccess: self.hasFullAccess)
        }
    }

    private func updateReturnKey() {
        let returnKeyType = textDocumentProxy.returnKeyType ?? .default
        keyboardView?.setReturnKeyTitle(Self.title(for: returnKeyType))
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
    func keyboardViewDidToggleTranslations(_ view: SayWellKeyboardView) {
        suggester.reset()
        view.syncSuggestionBarToggle()
        refreshSuggestion()
    }

    func keyboardViewDidChangeTone(_ view: SayWellKeyboardView) {
        view.syncSuggestionBarTone()
        suggester.prepareForToneChange()
        toneHintTask?.cancel()
        toneHintTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            view.endToneModeHint()
            self.refreshSuggestion()
        }
    }

    func keyboardView(_ view: SayWellKeyboardView, didTapKey key: KeyboardKey) {
        switch key {
        case .character(let value):
            if view.consumeCharacterForEmojiSearch(value) { break }
            textDocumentProxy.insertText(value)
            refreshSuggestion()
        case .space:
            if view.consumeSpaceForEmojiSearch() { break }
            textDocumentProxy.insertText(" ")
            refreshSuggestion()
        case .returnKey:
            textDocumentProxy.insertText("\n")
            suggester.reset()
        case .backspace:
            if view.consumeBackspaceForEmojiSearch() { break }
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
            view.toggleEmoji()
        case .acceptSuggestion:
            if case let .ready(phrase, charCount, translation) = view.currentSuggestion {
                insertTranslation(translation.translation, replacingPhrase: phrase, charCount: charCount)
            }
        }
    }
}
