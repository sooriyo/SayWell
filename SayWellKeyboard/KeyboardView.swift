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
    private var shiftEnabled = false
    private var shiftLocked = false
    private var showingNumbers = false
    private var returnTitle = "return"

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

    /// Native-ish horizontal gap between letter keys.
    private let keySpacing: CGFloat = 6
    private let rowSpacing: CGFloat = 11

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardPalette.background
        buildChrome()
        rebuildKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        shiftEnabled = false
        shiftLocked = false
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
        rowsStack.distribution = .fillEqually
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(suggestionBar)
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            suggestionBar.heightAnchor.constraint(equalToConstant: 36),

            rowsStack.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: 6),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            rowsStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
    }

    private func rebuildKeys() {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows = showingNumbers ? numberRows : letterRows
        for (index, row) in rows.enumerated() {
            rowsStack.addArrangedSubview(makeLetterRow(row, rowIndex: index))
        }
        rowsStack.addArrangedSubview(makeBottomRow())
    }

    private func makeLetterRow(_ characters: [String], rowIndex: Int) -> UIView {
        let letters = UIStackView()
        letters.axis = .horizontal
        letters.spacing = keySpacing
        letters.alignment = .fill
        letters.distribution = .fillEqually

        for raw in characters {
            let value = displayValue(for: raw)
            let button = KeyButton(style: .letter)
            button.setTitle(value, for: .normal)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .character(value))
                self.consumeShiftAfterCharacter()
            }, for: .touchUpInside)
            letters.addArrangedSubview(button)
        }

        if !showingNumbers, rowIndex == 1 {
            let wrapper = UIStackView()
            wrapper.axis = .horizontal
            wrapper.addArrangedSubview(flexibleSpacer(15))
            wrapper.addArrangedSubview(letters)
            wrapper.addArrangedSubview(flexibleSpacer(15))
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
                shift.setSymbol(systemName: symbol)
                if shiftEnabled || shiftLocked {
                    shift.setActionHighlighted(true)
                }
                shift.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.keyboardView(self, didTapKey: .shift)
                }, for: .touchUpInside)
                shift.widthAnchor.constraint(equalToConstant: 44).isActive = true
                row.addArrangedSubview(shift)
            } else {
                row.addArrangedSubview(flexibleSpacer(44))
            }

            row.addArrangedSubview(letters)

            let delete = KeyButton(style: .action)
            delete.setSymbol(systemName: "delete.left")
            delete.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .backspace)
            }, for: .touchUpInside)
            delete.widthAnchor.constraint(equalToConstant: 44).isActive = true
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
        layout.widthAnchor.constraint(equalToConstant: 44).isActive = true
        layout.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .layoutToggle)
        }, for: .touchUpInside)

        let globe = KeyButton(style: .action)
        globe.setSymbol(systemName: "globe")
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        globe.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .globe)
        }, for: .touchUpInside)

        let space = KeyButton(style: .space)
        space.setTitle("space", for: .normal)
        space.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        space.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .space)
        }, for: .touchUpInside)

        let ret = KeyButton(style: .returnKey)
        ret.setTitle(returnTitle, for: .normal)
        ret.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        ret.widthAnchor.constraint(equalToConstant: 92).isActive = true
        ret.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .returnKey)
        }, for: .touchUpInside)

        stack.addArrangedSubview(layout)
        stack.addArrangedSubview(globe)
        stack.addArrangedSubview(space)
        stack.addArrangedSubview(ret)
        return stack
    }

    private func displayValue(for raw: String) -> String {
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

// MARK: - Suggestion bar (native predictive height)

final class SuggestionBarView: UIView {
    var onTapAccept: (() -> Void)?

    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let separatorTop = UIView()
    private let separatorBottom = UIView()
    private var canAccept = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        separatorTop.backgroundColor = KeyboardPalette.separator
        separatorBottom.backgroundColor = KeyboardPalette.separator
        separatorTop.translatesAutoresizingMaskIntoConstraints = false
        separatorBottom.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textAlignment = .center
        label.textColor = KeyboardPalette.secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75

        spinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        spinner.hidesWhenStopped = true
        spinner.color = KeyboardPalette.secondaryLabel

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(separatorTop)
        addSubview(separatorBottom)
        addSubview(stack)

        NSLayoutConstraint.activate([
            separatorTop.topAnchor.constraint(equalTo: topAnchor),
            separatorTop.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorTop.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorTop.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            separatorBottom.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorBottom.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorBottom.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorBottom.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        apply(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshColors() {
        separatorTop.backgroundColor = KeyboardPalette.separator
        separatorBottom.backgroundColor = KeyboardPalette.separator
        spinner.color = KeyboardPalette.secondaryLabel
    }

    func apply(_ state: TranslationSuggester.SuggestionState) {
        canAccept = false
        switch state {
        case .idle:
            spinner.stopAnimating()
            label.text = ""
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 16, weight: .regular)

        case .needsFullAccess:
            spinner.stopAnimating()
            label.text = "Allow Full Access to translate"
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 15, weight: .regular)

        case .loading:
            spinner.startAnimating()
            label.text = ""
            label.textColor = KeyboardPalette.label

        case .ready(_, let translation):
            spinner.stopAnimating()
            canAccept = true
            label.text = translation.translation
            label.textColor = KeyboardPalette.label
            label.font = .systemFont(ofSize: 16, weight: .medium)

        case .failed(_, let message):
            spinner.stopAnimating()
            label.text = message
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 14, weight: .regular)
        }
    }

    @objc private func handleTap() {
        guard canAccept else { return }
        onTapAccept?()
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

    func setSymbol(systemName: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        setTitle(nil, for: .normal)
        tintColor = KeyboardPalette.label
    }

    func setActionHighlighted(_ highlighted: Bool) {
        isActionHighlighted = highlighted
        backgroundColor = highlighted ? KeyboardPalette.key : KeyboardPalette.actionKey
    }

    private func configures() {
        titleLabel?.font = .systemFont(ofSize: style == .letter ? 22.5 : 16, weight: .regular)
        setTitleColor(style == .returnKey ? .white : KeyboardPalette.label, for: .normal)
        backgroundColor = styleBackground
        layer.cornerRadius = 5
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.18
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true

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

// MARK: - Native-like palette

enum KeyboardPalette {
    static var background: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
                : UIColor(red: 0.82, green: 0.835, blue: 0.86, alpha: 1)
        }
    }

    static var key: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.39, green: 0.39, blue: 0.40, alpha: 1)
                : .white
        }
    }

    static var actionKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 1)
                : UIColor(red: 0.675, green: 0.70, blue: 0.735, alpha: 1)
        }
    }

    static var returnKey: UIColor {
        .systemBlue
    }

    static var label: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
    }

    static var secondaryLabel: UIColor {
        .secondaryLabel
    }

    static var separator: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.12)
        }
    }
}
