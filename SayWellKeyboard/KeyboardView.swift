import UIKit

enum KeyboardKey: Equatable {
    case character(String)
    case space
    case returnKey
    case backspace
    case shift
    case layoutToggle
    case globe
    case acceptSuggestion
}

protocol SayWellKeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: SayWellKeyboardView, didTapKey key: KeyboardKey)
}

final class SayWellKeyboardView: UIView {
    weak var delegate: SayWellKeyboardViewDelegate?

    private(set) var currentSuggestion: TranslationSuggester.SuggestionState = .idle

    private let suggestionBar = SuggestionBarView()
    private let rowsStack = UIStackView()
    private var shiftEnabled = true
    private var shiftLocked = false
    private var showingNumbers = false
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
        backgroundColor = KeyboardPalette.background
        isOpaque = true
        buildChrome()
        rebuildKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        backgroundColor = KeyboardPalette.background
        rebuildKeys()
        suggestionBar.refreshColors()
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
        showingNumbers.toggle()
        if !showingNumbers {
            shiftEnabled = true
            shiftLocked = false
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

        addSubview(suggestionBar)
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            // Compact predictive strip — no tall empty overlay above the keys.
            suggestionBar.topAnchor.constraint(equalTo: topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            suggestionBar.heightAnchor.constraint(equalToConstant: suggestionHeight),

            rowsStack.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: topKeysInset),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: sideInset),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -sideInset),
            // Pin keys to the bottom so leftover height can't become empty gray.
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
        ])
    }

    private func rebuildKeys() {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows = showingNumbers ? numberRows : letterRows
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
            // Native always draws uppercase glyphs on letter keys.
            button.setTitle(showingNumbers ? raw : raw.uppercased(), for: .normal)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .character(insert))
                self.consumeShiftAfterCharacter()
            }, for: .touchUpInside)
            letters.addArrangedSubview(button)
        }

        if !showingNumbers, rowIndex == 1 {
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

            if !showingNumbers {
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
            } else {
                row.addArrangedSubview(flexibleSpacer(42))
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

        let layout = KeyButton(style: .action)
        layout.setTitle(showingNumbers ? "ABC" : "123", for: .normal)
        layout.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        layout.widthAnchor.constraint(equalToConstant: 42).isActive = true
        layout.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .layoutToggle)
        }, for: .touchUpInside)
        stack.addArrangedSubview(layout)

        // Native puts emoji here; we use globe when the system asks for an input-mode switch.
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

    private func insertValue(for raw: String) -> String {
        guard !showingNumbers else { return raw }
        if shiftEnabled || shiftLocked {
            return raw.uppercased()
        }
        return raw
    }

    private func consumeShiftAfterCharacter() {
        guard !showingNumbers, shiftEnabled, !shiftLocked else { return }
        shiftEnabled = false
        rebuildKeys()
    }

    private func flexibleSpacer(_ width: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }
}

// MARK: - Native-style 3-slot predictive bar

final class SuggestionBarView: UIView {
    var onTapAccept: (() -> Void)?

    private let leftLabel = UILabel()
    private let centerLabel = UILabel()
    private let rightLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let divider1 = UIView()
    private let divider2 = UIView()
    private var canAccept = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardPalette.background
        isOpaque = true

        for label in [leftLabel, centerLabel, rightLabel] {
            label.font = .systemFont(ofSize: 17, weight: .regular)
            label.textAlignment = .center
            label.textColor = KeyboardPalette.label
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
        }

        spinner.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
        spinner.hidesWhenStopped = true
        spinner.color = KeyboardPalette.secondaryLabel

        divider1.backgroundColor = KeyboardPalette.separator
        divider2.backgroundColor = KeyboardPalette.separator

        let leftSlot = slotView(containing: leftLabel)
        let centerSlot = slotView(containing: centerLabel, spinner: spinner)
        let rightSlot = slotView(containing: rightLabel)

        let stack = UIStackView(arrangedSubviews: [leftSlot, divider1, centerSlot, divider2, rightSlot])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            divider1.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            divider2.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            leftSlot.widthAnchor.constraint(equalTo: centerSlot.widthAnchor),
            rightSlot.widthAnchor.constraint(equalTo: centerSlot.widthAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        apply(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshColors() {
        backgroundColor = KeyboardPalette.background
        divider1.backgroundColor = KeyboardPalette.separator
        divider2.backgroundColor = KeyboardPalette.separator
        spinner.color = KeyboardPalette.secondaryLabel
    }

    func apply(_ state: TranslationSuggester.SuggestionState) {
        canAccept = false
        leftLabel.text = nil
        rightLabel.text = nil
        centerLabel.textColor = KeyboardPalette.label
        centerLabel.font = .systemFont(ofSize: 17, weight: .regular)

        switch state {
        case .idle:
            spinner.stopAnimating()
            centerLabel.text = nil

        case .needsFullAccess:
            spinner.stopAnimating()
            centerLabel.text = "Allow Full Access"
            centerLabel.textColor = KeyboardPalette.secondaryLabel
            centerLabel.font = .systemFont(ofSize: 15, weight: .regular)

        case .loading:
            spinner.startAnimating()
            centerLabel.text = nil

        case .ready(_, let translation):
            spinner.stopAnimating()
            canAccept = true
            centerLabel.text = translation.translation
            centerLabel.font = .systemFont(ofSize: 17, weight: .regular)

        case .failed(_, let message):
            spinner.stopAnimating()
            centerLabel.text = message
            centerLabel.textColor = KeyboardPalette.secondaryLabel
            centerLabel.font = .systemFont(ofSize: 14, weight: .regular)
        }
    }

    @objc private func handleTap() {
        guard canAccept else { return }
        onTapAccept?()
    }

    private func slotView(containing label: UILabel, spinner: UIActivityIndicatorView? = nil) -> UIView {
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        if let spinner {
            spinner.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }

        return container
    }
}

// MARK: - Key button

final class KeyButton: UIButton {
    enum Style {
        case letter, action, space, returnKey
    }

    private let style: Style
    private var isActionHighlighted = false

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
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        setTitle(nil, for: .normal)
        tintColor = KeyboardPalette.label
    }

    func setActionHighlighted(_ highlighted: Bool) {
        isActionHighlighted = highlighted
        backgroundColor = highlighted ? KeyboardPalette.key : KeyboardPalette.actionKey
    }

    private func configures() {
        titleLabel?.font = .systemFont(ofSize: style == .letter ? 22.5 : 16, weight: .light)
        setTitleColor(style == .returnKey ? .white : KeyboardPalette.label, for: .normal)
        backgroundColor = styleBackground
        layer.cornerRadius = 4.5
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.4 : 0.25
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
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
        case .letter, .space:
            backgroundColor = KeyboardPalette.actionKey
        case .action:
            backgroundColor = KeyboardPalette.key
        case .returnKey:
            backgroundColor = KeyboardPalette.returnKey.withAlphaComponent(0.85)
        }
    }

    @objc private func touchUp() {
        backgroundColor = styleBackground
    }
}

// MARK: - Palette

enum KeyboardPalette {
    /// Match the host app chrome (Messages composer) so the top seam disappears.
    static var background: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            }
            // Same white as the Messages input bar in the red-box area.
            return .systemBackground
        }
    }

    static var key: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.42, green: 0.42, blue: 0.43, alpha: 1)
                : .white
        }
    }

    static var actionKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 1)
                : UIColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1)
        }
    }

    static var returnKey: UIColor { .systemBlue }

    static var label: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
    }

    static var secondaryLabel: UIColor { .secondaryLabel }

    static var separator: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor.black.withAlphaComponent(0.12)
        }
    }
}
