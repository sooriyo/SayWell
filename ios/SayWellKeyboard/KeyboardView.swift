import UIKit

enum KeyboardKey: Equatable {
    case character(String)
    case space
    case returnKey
    case backspace
    case shift
    case layoutToggle
    case symbolsToggle
    case globe
    case emoji
    case acceptSuggestion
}

private enum KeyboardLayout {
    case letters
    case numbers
    case symbols
}

protocol SayWellKeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: SayWellKeyboardView, didTapKey key: KeyboardKey)
}

final class SayWellKeyboardView: UIView {
    weak var delegate: SayWellKeyboardViewDelegate?

    private(set) var currentSuggestion: TranslationSuggester.SuggestionState = .idle

    private let suggestionBar = SuggestionBarView()
    private let rowsStack = UIStackView()
    private let keyPreview = KeyPreviewView()
    private var shiftEnabled = false
    private var shiftLocked = false
    private var layout: KeyboardLayout = .letters
    private var returnTitle = "return"
    private var showsGlobe = true

    private let letterRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    private let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    private let symbolRows: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    /// Native-like metrics — keep total height tight so we don't overlay the host UI.
    private let keySpacing: CGFloat = 6
    private let rowSpacing: CGFloat = 10
    private let keyHeight: CGFloat = 42
    private let sideInset: CGFloat = 3
    private let suggestionHeight: CGFloat = 36
    private let topKeysInset: CGFloat = 6
    private let bottomInset: CGFloat = 6

    /// Tight height: suggestion(36) + gap(6) + 4×42 keys + 3×10 gaps + bottom(6).
    static let preferredHeight: CGFloat = 246

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Native keyboard is translucent glass — no solid fill.
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        buildChrome()
        rebuildKeys()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: SayWellKeyboardView, _) in
            self.rebuildKeys()
            self.suggestionBar.refreshColors()
            self.keyPreview.refreshColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        print("🎹 [HITTEST CALLED] point=\(point)")

        // First, try the normal hit-test (suggestion bar, previews, etc.)
        if let view = super.hitTest(point, with: event), view !== self {
            print("🎹 [HITTEST] Normal hit returned: \(type(of: view))")
            return view
        }

        // If no view hit, find the closest key button (native keyboard behavior)
        var closestButton: KeyButton?
        var closestDistance = CGFloat.infinity
        var buttonCount = 0

        func findClosestButton(in view: UIView) {
            for subview in view.subviews {
                if let button = subview as? KeyButton {
                    buttonCount += 1
                    // Convert button's center from its coordinate system to self's
                    let buttonCenter = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
                    let buttonCenterInSelf = convert(buttonCenter, from: button)
                    let distance = hypot(point.x - buttonCenterInSelf.x, point.y - buttonCenterInSelf.y)
                    if distance < closestDistance {
                        closestDistance = distance
                        closestButton = button
                    }
                } else {
                    findClosestButton(in: subview)
                }
            }
        }

        findClosestButton(in: self)

        if let button = closestButton {
            print("🎹 hitTest: Found \(buttonCount) buttons, closest at distance \(closestDistance)")
            return button
        } else {
            print("🎹 hitTest: No buttons found (found \(buttonCount) buttons)")
            return nil
        }
    }

    func apply(suggestion: TranslationSuggester.SuggestionState) {
        currentSuggestion = suggestion
        suggestionBar.apply(suggestion)
    }

    func setReturnKeyTitle(_ title: String) {
        returnTitle = title
        rebuildKeys()
    }

    func setNeedsInputModeSwitchKey(_ needs: Bool) {
        guard showsGlobe != needs else { return }
        showsGlobe = needs
        rebuildKeys()
    }

    func toggleShift() {
        if shiftLocked {
            shiftLocked = false
            shiftEnabled = false
        } else if shiftEnabled {
            shiftLocked = true
        } else {
            shiftEnabled = true
        }
        rebuildKeys()
    }

    func toggleLayout() {
        switch layout {
        case .letters:
            layout = .numbers
            shiftEnabled = false
            shiftLocked = false
        case .numbers, .symbols:
            layout = .letters
            shiftEnabled = false
            shiftLocked = false
        }
        rebuildKeys()
    }

    func toggleSymbols() {
        switch layout {
        case .numbers:
            layout = .symbols
        case .symbols:
            layout = .numbers
        case .letters:
            break
        }
        rebuildKeys()
    }

    private func buildChrome() {
        suggestionBar.translatesAutoresizingMaskIntoConstraints = false
        suggestionBar.onTapAccept = { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .acceptSuggestion)
        }

        rowsStack.axis = .vertical
        rowsStack.spacing = rowSpacing
        rowsStack.alignment = .fill
        rowsStack.distribution = .fill
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.clipsToBounds = false

        addSubview(suggestionBar)
        addSubview(rowsStack)
        addSubview(keyPreview)

        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            suggestionBar.heightAnchor.constraint(equalToConstant: suggestionHeight),

            rowsStack.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: topKeysInset),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: sideInset),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -sideInset),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
        ])
    }

    private func rebuildKeys() {
        keyPreview.dismiss(animated: false)
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows: [[String]]
        switch layout {
        case .letters:
            rows = letterRows
        case .numbers:
            rows = numberRows
        case .symbols:
            rows = symbolRows
        }

        for (index, row) in rows.enumerated() {
            let rowView = makeLetterRow(row, rowIndex: index)
            rowView.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
            rowsStack.addArrangedSubview(rowView)
        }
        let bottom = makeBottomRow()
        bottom.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
        rowsStack.addArrangedSubview(bottom)
    }

    private func makeLetterRow(_ characters: [String], rowIndex: Int) -> UIView {
        let letters = UIStackView()
        letters.axis = .horizontal
        letters.spacing = keySpacing
        letters.alignment = .fill
        letters.distribution = .fillEqually

        for raw in characters {
            let insert = insertValue(for: raw)
            let button = KeyButton(style: .letter)
            button.setTitle(displayTitle(for: raw), for: .normal)
            wireKeyPreview(for: button)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .character(insert))
                self.consumeShiftAfterCharacter()
            }, for: .touchUpInside)
            letters.addArrangedSubview(button)
        }

        if layout == .letters, rowIndex == 1 {
            let wrapper = UIStackView()
            wrapper.axis = .horizontal
            wrapper.addArrangedSubview(flexibleSpacer(18))
            wrapper.addArrangedSubview(letters)
            wrapper.addArrangedSubview(flexibleSpacer(18))
            return wrapper
        }

        if rowIndex == 2 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = keySpacing
            row.alignment = .fill
            row.distribution = .fill

            switch layout {
            case .letters:
                let shift = KeyButton(style: .action)
                let symbol = shiftLocked ? "capslock.fill" : (shiftEnabled ? "shift.fill" : "shift")
                shift.setSymbol(systemName: symbol, pointSize: 15)
                if shiftEnabled || shiftLocked {
                    shift.setActionHighlighted(true)
                }
                shift.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.keyboardView(self, didTapKey: .shift)
                }, for: .touchUpInside)
                shift.widthAnchor.constraint(equalToConstant: 42).isActive = true
                row.addArrangedSubview(shift)

            case .numbers:
                let symbols = KeyButton(style: .action)
                symbols.setTitle("#+=", for: .normal)
                symbols.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
                symbols.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.keyboardView(self, didTapKey: .symbolsToggle)
                }, for: .touchUpInside)
                symbols.widthAnchor.constraint(equalToConstant: 42).isActive = true
                row.addArrangedSubview(symbols)

            case .symbols:
                let numbers = KeyButton(style: .action)
                numbers.setTitle("123", for: .normal)
                numbers.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
                numbers.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.keyboardView(self, didTapKey: .symbolsToggle)
                }, for: .touchUpInside)
                numbers.widthAnchor.constraint(equalToConstant: 42).isActive = true
                row.addArrangedSubview(numbers)
            }

            row.addArrangedSubview(letters)

            let delete = KeyButton(style: .action)
            delete.setSymbol(systemName: "delete.left", pointSize: 16)
            delete.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .backspace)
            }, for: .touchUpInside)
            delete.widthAnchor.constraint(equalToConstant: 42).isActive = true
            row.addArrangedSubview(delete)
            return row
        }

        return letters
    }

    private func makeBottomRow() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = keySpacing
        stack.alignment = .fill
        stack.distribution = .fill

        let layoutKey = KeyButton(style: .action)
        layoutKey.setTitle(layout == .letters ? "123" : "ABC", for: .normal)
        layoutKey.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        layoutKey.widthAnchor.constraint(equalToConstant: 42).isActive = true
        layoutKey.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .layoutToggle)
        }, for: .touchUpInside)
        stack.addArrangedSubview(layoutKey)

        if showsGlobe {
            let globe = KeyButton(style: .action)
            globe.setSymbol(systemName: "globe", pointSize: 16)
            globe.widthAnchor.constraint(equalToConstant: 42).isActive = true
            globe.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .globe)
            }, for: .touchUpInside)
            stack.addArrangedSubview(globe)
        }

        let emoji = KeyButton(style: .action)
        emoji.setSymbol(systemName: "face.smiling", pointSize: 16)
        emoji.widthAnchor.constraint(equalToConstant: 42).isActive = true
        emoji.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .emoji)
        }, for: .touchUpInside)
        stack.addArrangedSubview(emoji)

        let space = KeyButton(style: .space)
        space.setTitle("space", for: .normal)
        space.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        space.setTitleColor(KeyboardPalette.secondaryLabel, for: .normal)
        space.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .space)
        }, for: .touchUpInside)
        stack.addArrangedSubview(space)

        let ret = KeyButton(style: usesBlueReturn ? .returnKey : .action)
        if usesBlueReturn {
            ret.setTitle(returnTitle, for: .normal)
            ret.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        } else {
            ret.setSymbol(systemName: "return.left", pointSize: 16)
        }
        ret.widthAnchor.constraint(equalToConstant: usesBlueReturn ? 88 : 88).isActive = true
        ret.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .returnKey)
        }, for: .touchUpInside)
        stack.addArrangedSubview(ret)

        return stack
    }

    /// Native blues the return key for go/search/send/etc.; plain return uses the arrow.
    private var usesBlueReturn: Bool {
        !["return", "default"].contains(returnTitle.lowercased())
    }

    private func displayTitle(for raw: String) -> String {
        guard layout == .letters else { return raw }
        if shiftEnabled || shiftLocked {
            return raw.uppercased()
        }
        return raw
    }

    private func insertValue(for raw: String) -> String {
        guard layout == .letters else { return raw }
        if shiftEnabled || shiftLocked {
            return raw.uppercased()
        }
        return raw
    }

    private func consumeShiftAfterCharacter() {
        guard layout == .letters, shiftEnabled, !shiftLocked else { return }
        shiftEnabled = false
        rebuildKeys()
    }

    private func flexibleSpacer(_ width: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    private func wireKeyPreview(for button: KeyButton) {
        button.onBeginPreview = { [weak self, weak button] in
            guard let self, let button else { return }
            self.showKeyPreview(for: button)
        }
        button.onEndPreview = { [weak self, weak button] in
            button?.setPreviewVisible(false)
            self?.keyPreview.dismiss()
        }
    }

    private func showKeyPreview(for button: KeyButton) {
        guard let title = button.title(for: .normal), !title.isEmpty else { return }
        keyPreview.present(text: title, sourceView: button, in: self)
        button.setPreviewVisible(true)
    }
}

// MARK: - Predictive strip (no plate — floats on system keyboard chrome)

/// Three pulsing dots — friendlier than a system spinner in the suggestion strip.
final class AnimatedEllipsisView: UIView {
    private let dotStack = UIStackView()
    private let dots: [UIView] = (0..<3).map { _ in UIView() }
    private var isAnimating = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        dotStack.axis = .horizontal
        dotStack.spacing = 4
        dotStack.alignment = .center
        dotStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotStack)

        for dot in dots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = KeyboardPalette.secondaryLabel
            dot.layer.cornerRadius = 3
            dotStack.addArrangedSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6),
            ])
        }

        NSLayoutConstraint.activate([
            dotStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        stopAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshColors() {
        dots.forEach { $0.backgroundColor = KeyboardPalette.secondaryLabel }
    }

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        animateDot(at: 0)
    }

    func stopAnimating() {
        isAnimating = false
        dots.forEach {
            $0.layer.removeAllAnimations()
            $0.alpha = 0.35
            $0.transform = .identity
        }
    }

    private func animateDot(at index: Int) {
        guard isAnimating else { return }
        let dot = dots[index]

        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            dot.alpha = 1
            dot.transform = CGAffineTransform(translationX: 0, y: -2)
        } completion: { [weak self] finished in
            guard let self, finished, self.isAnimating else { return }
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction]
            ) {
                dot.alpha = 0.35
                dot.transform = .identity
            } completion: { [weak self] finished in
                guard let self, finished, self.isAnimating else { return }
                self.animateDot(at: (index + 1) % self.dots.count)
            }
        }
    }
}

final class SuggestionBarView: UIView {
    var onTapAccept: (() -> Void)?

    private let contentStack = UIStackView()
    private let ellipsis = AnimatedEllipsisView()
    private let label = UILabel()
    private var canAccept = false
    private var displayedState: TranslationSuggester.SuggestionState = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textAlignment = .center
        label.textColor = KeyboardPalette.label
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.numberOfLines = 1

        ellipsis.setContentHuggingPriority(.required, for: .horizontal)
        ellipsis.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(ellipsis)
        contentStack.addArrangedSubview(label)
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12).withPriority(.defaultHigh),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12).withPriority(.defaultHigh),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        apply(.idle, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshColors() {
        backgroundColor = .clear
        ellipsis.refreshColors()
    }

    func apply(_ state: TranslationSuggester.SuggestionState) {
        apply(state, animated: state != displayedState)
    }

    private func apply(_ state: TranslationSuggester.SuggestionState, animated: Bool) {
        let stateChanged = state != displayedState
        let previousState = displayedState
        displayedState = state

        let shouldAnimate = animated && stateChanged && state != .idle

        guard shouldAnimate else {
            render(state)
            label.alpha = 1
            label.transform = .identity
            return
        }

        let wasShowingEllipsis: Bool
        if case .loading = previousState { wasShowingEllipsis = true } else { wasShowingEllipsis = false }
        let willShowEllipsis: Bool
        if case .loading = state { willShowEllipsis = true } else { willShowEllipsis = false }

        label.alpha = 0
        label.transform = CGAffineTransform(translationX: 0, y: 3)

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            if wasShowingEllipsis {
                self.ellipsis.alpha = 0
            }
        } completion: { _ in
            self.render(state)
            self.ellipsis.alpha = willShowEllipsis ? 0 : 1

            UIView.animate(
                withDuration: 0.26,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.35,
                options: [.allowUserInteraction]
            ) {
                self.label.alpha = 1
                self.label.transform = .identity
                if willShowEllipsis {
                    self.ellipsis.alpha = 1
                }
            }
        }
    }

    private func render(_ state: TranslationSuggester.SuggestionState) {
        canAccept = false
        label.textColor = KeyboardPalette.label
        label.font = .systemFont(ofSize: 17, weight: .regular)
        ellipsis.isHidden = true
        ellipsis.stopAnimating()

        switch state {
        case .idle:
            label.text = "Type Singlish — tap suggestion for English"
            label.textColor = KeyboardPalette.tertiaryLabel
            label.font = .systemFont(ofSize: 14, weight: .regular)

        case .needsFullAccess:
            label.text = "Turn on Full Access to translate"
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 15, weight: .regular)

        case .loading(let phrase, _):
            ellipsis.isHidden = false
            ellipsis.startAnimating()
            label.text = Self.loadingMessage(for: phrase)
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 15, weight: .regular)

        case .ready(_, _, let translation):
            canAccept = true
            label.text = translation.translation

        case .failed(_, _, let message):
            label.text = Self.friendlyFailureMessage(message)
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 14, weight: .regular)
        }
    }

    private static func loadingMessage(for phrase: String) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Finding the right English" }

        if trimmed.count <= 22 {
            return "“\(trimmed)” → English"
        }
        return "Translating your Singlish"
    }

    private static func friendlyFailureMessage(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("rate limit") || lower.contains("too many") {
            return "Slow down a bit — try again soon"
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "Taking too long — try again"
        }
        if lower.contains("network") || lower.contains("internet") || lower.contains("offline") {
            return "No connection — check your network"
        }
        return "Couldn't translate — try again"
    }

    @objc private func handleTap() {
        guard canAccept else { return }
        onTapAccept?()
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - Key button

final class KeyButton: UIButton {
    enum Style {
        case letter, action, space, returnKey
    }

    private let style: Style
    private var isActionHighlighted = false
    var onBeginPreview: (() -> Void)?
    var onEndPreview: (() -> Void)?

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        configures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSymbol(systemName: String, pointSize: CGFloat = 17) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        setTitle(nil, for: .normal)
        tintColor = KeyboardPalette.label
    }

    func setActionHighlighted(_ highlighted: Bool) {
        isActionHighlighted = highlighted
        backgroundColor = highlighted ? KeyboardPalette.key : KeyboardPalette.actionKey
    }

    func setPreviewVisible(_ visible: Bool) {
        UIView.animate(withDuration: visible ? 0.05 : 0.04, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.titleLabel?.alpha = visible ? 0 : 1
            self.backgroundColor = visible ? .clear : self.styleBackground
        }
    }

    private func configures() {
        titleLabel?.font = .systemFont(
            ofSize: style == .letter ? 22 : 16,
            weight: style == .letter ? .regular : .medium
        )
        setTitleColor(style == .returnKey ? .white : KeyboardPalette.label, for: .normal)
        backgroundColor = styleBackground
        layer.cornerRadius = 5.5
        layer.masksToBounds = true

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    private var styleBackground: UIColor {
        switch style {
        case .letter, .space:
            return KeyboardPalette.key
        case .action:
            return isActionHighlighted ? KeyboardPalette.key : KeyboardPalette.actionKey
        case .returnKey:
            return KeyboardPalette.returnKey
        }
    }

    @objc private func touchDown() {
        switch style {
        case .letter:
            break // preview bubble handles pressed visuals
        case .space:
            backgroundColor = KeyboardPalette.actionKey
        case .action:
            backgroundColor = KeyboardPalette.key
        case .returnKey:
            backgroundColor = KeyboardPalette.returnKey.withAlphaComponent(0.85)
        }
        if style == .letter {
            onBeginPreview?()
        }
    }

    @objc private func touchUp() {
        backgroundColor = styleBackground
        if style == .letter {
            onEndPreview?()
        }
    }
}

// MARK: - Key preview

private final class KeyPreviewView: UIView {
    private let plate = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        alpha = 0
        clipsToBounds = false

        plate.layer.cornerRadius = 6
        plate.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 36, weight: .regular)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(plate)
        plate.addSubview(label)

        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(equalTo: leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: trailingAnchor),
            plate.topAnchor.constraint(equalTo: topAnchor),
            plate.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.centerXAnchor.constraint(equalTo: plate.centerXAnchor),
            label.topAnchor.constraint(equalTo: plate.topAnchor, constant: 4),
        ])

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)

        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshColors() {
        plate.backgroundColor = KeyboardPalette.previewKey
        label.textColor = KeyboardPalette.label
    }

    func present(text: String, sourceView: UIView, in container: UIView) {
        label.text = text

        let sourceFrame = sourceView.convert(sourceView.bounds, to: container)
        let width = max(sourceFrame.width * 1.3, 44)
        let extensionAbove: CGFloat = 26
        let height = sourceFrame.height + extensionAbove
        let horizontalInset: CGFloat = 3

        var x = sourceFrame.midX - width / 2
        x = max(horizontalInset, min(x, container.bounds.width - width - horizontalInset))

        let y = sourceFrame.minY - extensionAbove

        frame = CGRect(x: x, y: y, width: width, height: height)
        container.bringSubviewToFront(self)
        isHidden = false

        if alpha < 1 || transform != .identity {
            transform = CGAffineTransform(scaleX: 0.82, y: 0.82).translatedBy(x: 0, y: 8)
            alpha = 0
            UIView.animate(
                withDuration: 0.09,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.8,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.alpha = 1
                self.transform = .identity
            }
        } else {
            alpha = 1
            transform = .identity
        }
    }

    func dismiss(animated: Bool = true) {
        guard !isHidden, alpha > 0 else {
            isHidden = true
            alpha = 0
            transform = .identity
            return
        }

        guard animated else {
            isHidden = true
            alpha = 0
            transform = .identity
            return
        }

        UIView.animate(
            withDuration: 0.06,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9).translatedBy(x: 0, y: 3)
        } completion: { _ in
            self.isHidden = true
            self.transform = .identity
        }
    }
}

// MARK: - Palette

enum KeyboardPalette {
    static var key: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.28)
                : UIColor(white: 1, alpha: 0.25)
        }
    }

    /// Pressed letter key + preview bubble — lighter and more opaque than resting keys.
    static var previewKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.57, green: 0.57, blue: 0.59, alpha: 0.95)
                : UIColor(white: 1, alpha: 1.0)
        }
    }

    static var actionKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.20)
                : UIColor(white: 1, alpha: 0.55)
        }
    }

    static var returnKey: UIColor { .systemBlue }

    static var label: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
    }

    static var secondaryLabel: UIColor { .secondaryLabel }

    static var tertiaryLabel: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.42)
                : UIColor.black.withAlphaComponent(0.38)
        }
    }
}
