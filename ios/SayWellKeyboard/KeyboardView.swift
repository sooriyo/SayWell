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
    case emoji
}

protocol SayWellKeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: SayWellKeyboardView, didTapKey key: KeyboardKey)
    func keyboardViewDidToggleTranslations(_ view: SayWellKeyboardView)
    func keyboardViewDidChangeTone(_ view: SayWellKeyboardView)
}

final class SayWellKeyboardView: UIView {
    weak var delegate: SayWellKeyboardViewDelegate?

    private(set) var currentSuggestion: TranslationSuggester.SuggestionState = .idle

    private let suggestionBar = SuggestionBarView()
    private let rowsStack = UIStackView()
    private let emojiPanel = EmojiPanelView()
    private let emojiCategoryBar = EmojiCategoryBarView()
    private let keyPreview = KeyPreviewView()
    private var shiftEnabled = false
    private var shiftLocked = false
    private var letterKeyEntries: [(button: KeyButton, raw: String)] = []
    private weak var shiftKeyButton: KeyButton?
    private var cachedKeyTargets: [KeyHitTarget] = []
    private var keyTargetsCacheValid = false
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
    private let keySpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 12
    private let keyHeight: CGFloat = 42
    /// Bottom row (space/return) gets extra height — easier to hit, matches native feel.
    private let bottomRowHeight: CGFloat = 46
    private let sideInset: CGFloat = 5
    private let suggestionHeight: CGFloat = 40
    private let topKeysInset: CGFloat = 6
    private let bottomInset: CGFloat = 4

    /// Keyboard extensions drop touches on fully transparent pixels before hit-testing.
    /// Root views stay `.clear` so the system tray shows through; keys handle their own hits.

    /// suggestion(36) + gap(6) + 3×42 + 46 bottom + 3×12 gaps + bottom(4).
    static let baseHeight: CGFloat = 258
    private static let letterBlockHeight: CGFloat = 42 * 3 + 12 * 2

    static var preferredHeight: CGFloat { baseHeight }

    var preferredContentHeight: CGFloat {
        if layout == .emoji, emojiSearchTyping {
            return Self.baseHeight + Self.letterBlockHeight
        }
        return Self.baseHeight
    }

    private var emojiSearchTyping = false

    /// Key currently tracked by the keyboard-level touch engine.
    private weak var activeKey: KeyButton?

    /// Collapses the suggestion bar in emoji mode (native emoji keyboard has no predictions).
    private var suggestionBarHeightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Transparent — system keyboard panel shows through for a native, attached look.
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isMultipleTouchEnabled = false
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
        CGSize(width: UIView.noIntrinsicMetric, height: preferredContentHeight)
    }

    var onPreferredHeightChange: (() -> Void)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if keyArea.contains(point) { return true }
        let suggestionPoint = convert(point, to: suggestionBar)
        if suggestionBar.bounds.contains(suggestionPoint) { return true }
        if layout == .emoji, !emojiPanel.isHidden {
            let panelPoint = convert(point, to: emojiPanel)
            if emojiPanel.bounds.contains(panelPoint) { return true }
        }
        return super.point(inside: point, with: event)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, bounds.contains(point) else {
            return nil
        }

        let suggestionPoint = convert(point, to: suggestionBar)
        if suggestionBar.bounds.contains(suggestionPoint),
           let suggestionHit = suggestionBar.hitTest(suggestionPoint, with: event) {
            return suggestionHit
        }

        if layout == .emoji, !emojiPanel.isHidden {
            let panelPoint = convert(point, to: emojiPanel)
            if emojiPanel.bounds.contains(panelPoint),
               let panelHit = emojiPanel.hitTest(panelPoint, with: event) {
                return panelHit
            }
        }

        if layout == .emoji, keyArea.contains(point) {
            let rowsPoint = convert(point, to: rowsStack)
            if let hit = rowsStack.hitTest(rowsPoint, with: event),
               hit !== self,
               !(hit is KeyButton) {
                return hit
            }
        }

        if keyArea.contains(point) {
            return self
        }

        return super.hitTest(point, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        pressKey(keyButton(at: touch.location(in: self)))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let next = keyButton(at: touch.location(in: self))
        guard next !== activeKey else { return }
        pressKey(next)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseActiveKey(commit: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseActiveKey(commit: false)
    }

    private var keyArea: CGRect {
        rowsStack.frame.insetBy(dx: -sideInset, dy: -(rowSpacing / 2))
    }

    private func pressKey(_ key: KeyButton?) {
        if activeKey === key { return }
        activeKey?.setPressed(false)
        activeKey = key
        key?.setPressed(true)
    }

    private func releaseActiveKey(commit: Bool) {
        let key = activeKey
        activeKey = nil
        key?.setPressed(false)
        if commit {
            key?.onTap?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildKeyTargetCache()
    }

    private func rebuildKeyTargetCache() {
        var targets: [KeyHitTarget] = []

        func visit(_ view: UIView) {
            for subview in view.subviews {
                if let button = subview as? KeyButton {
                    targets.append(
                        KeyHitTarget(
                            button: button,
                            frame: button.convert(button.bounds, to: self)
                        )
                    )
                } else {
                    visit(subview)
                }
            }
        }

        visit(rowsStack)
        cachedKeyTargets = targets
        keyTargetsCacheValid = true
    }

    /// Maps a touch to the best key target.
    ///
    /// Uses a two-pass strategy:
    /// 1. Exact frame hit — wins for wide keys (space, return) whose corners are far from center.
    /// 2. Expanded-frame distance — for inter-key gaps and row gutters (native-like slop).
    private func keyButton(at point: CGPoint) -> KeyButton? {
        guard keyArea.contains(point) else { return nil }

        // Slightly generous vs half-spacing — native keyboards forgive corner/edge taps.
        let slopX: CGFloat = keySpacing / 2
        let slopY: CGFloat = rowSpacing / 2
        let cornerPad: CGFloat = 3
        let buttons = collectKeyButtons()

        // Pass 1: visual bounds + a few pt of corner/edge forgiveness.
        // Prefer the key whose edge is closest (not center-distance), then smallest key.
        let paddedHits = buttons.filter {
            $0.frame.insetBy(dx: -cornerPad, dy: -cornerPad).contains(point)
        }
        if let hit = paddedHits.min(by: { lhs, rhs in
            let left = lhs.edgeDistance(to: point)
            let right = rhs.edgeDistance(to: point)
            if left != right { return left < right }
            if lhs.area != rhs.area { return lhs.area < rhs.area }
            return abs(point.y - lhs.frame.midY) < abs(point.y - rhs.frame.midY)
        }) {
            return hit.button
        }

        // Pass 2: gap / near-miss — nearest expanded rect; ties prefer smaller, then vertically closer key.
        var best: KeyButton?
        var bestDistance = CGFloat.infinity
        var bestArea = CGFloat.infinity
        var bestVerticalDelta = CGFloat.infinity

        for item in buttons {
            let expanded = item.frame.insetBy(dx: -slopX, dy: -slopY)
            let distance = Self.distance(from: point, to: expanded)
            let verticalDelta = abs(point.y - item.frame.midY)

            let isBetter = distance < bestDistance
                || (distance == bestDistance && item.area < bestArea)
                || (distance == bestDistance && item.area == bestArea && verticalDelta < bestVerticalDelta)

            if isBetter {
                bestDistance = distance
                bestArea = item.area
                bestVerticalDelta = verticalDelta
                best = item.button
            }
        }

        return best
    }

    private struct KeyHitTarget {
        let button: KeyButton
        let frame: CGRect
        var area: CGFloat { frame.width * frame.height }

        func edgeDistance(to point: CGPoint) -> CGFloat {
            SayWellKeyboardView.distance(from: point, to: frame)
        }
    }

    private func collectKeyButtons() -> [KeyHitTarget] {
        if keyTargetsCacheValid {
            return cachedKeyTargets
        }

        var targets: [KeyHitTarget] = []

        func visit(_ view: UIView) {
            for subview in view.subviews {
                if let button = subview as? KeyButton {
                    targets.append(
                        KeyHitTarget(
                            button: button,
                            frame: button.convert(button.bounds, to: self)
                        )
                    )
                } else {
                    visit(subview)
                }
            }
        }

        visit(rowsStack)
        cachedKeyTargets = targets
        keyTargetsCacheValid = true
        return targets
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    func apply(suggestion: TranslationSuggester.SuggestionState) {
        currentSuggestion = suggestion
        suggestionBar.apply(suggestion)
    }

    func syncSuggestionBarToggle() {
        suggestionBar.syncToggleState()
        suggestionBar.syncToneState()
    }

    func syncSuggestionBarTone() {
        suggestionBar.syncToneState()
    }

    func endToneModeHint() {
        suggestionBar.endToneModeHint()
    }

    func setReturnKeyTitle(_ title: String) {
        guard returnTitle != title else { return }
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
        if usesLetterKeyLayout, !letterKeyEntries.isEmpty {
            refreshLetterKeyTitles()
        } else {
            rebuildKeys()
        }
    }

    func toggleEmoji() {
        if layout == .emoji {
            layout = .letters
            emojiSearchTyping = false
            emojiPanel.endSearch()
        } else {
            layout = .emoji
            shiftEnabled = false
            shiftLocked = false
        }
        rebuildKeys()
    }

    /// Routes typing to emoji search when the search field is active.
    func consumeCharacterForEmojiSearch(_ value: String) -> Bool {
        guard layout == .emoji, emojiPanel.isSearchActive else { return false }
        return emojiPanel.insertSearchCharacter(value)
    }

    func consumeBackspaceForEmojiSearch() -> Bool {
        guard layout == .emoji, emojiPanel.isSearchActive else { return false }
        return emojiPanel.deleteSearchCharacter()
    }

    func consumeSpaceForEmojiSearch() -> Bool {
        guard layout == .emoji, emojiPanel.isSearchActive else { return false }
        return emojiPanel.insertSearchCharacter(" ")
    }

    func toggleLayout() {
        if layout == .emoji {
            layout = .letters
            rebuildKeys()
            return
        }

        switch layout {
        case .letters:
            layout = .numbers
            shiftEnabled = false
            shiftLocked = false
        case .numbers, .symbols:
            layout = .letters
            shiftEnabled = false
            shiftLocked = false
        case .emoji:
            break
        }
        rebuildKeys()
    }

    func toggleSymbols() {
        switch layout {
        case .numbers:
            layout = .symbols
        case .symbols:
            layout = .numbers
        case .letters, .emoji:
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
        suggestionBar.onToggleTranslations = { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardViewDidToggleTranslations(self)
        }
        suggestionBar.onCycleTone = { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardViewDidChangeTone(self)
        }

        rowsStack.axis = .vertical
        rowsStack.spacing = rowSpacing
        rowsStack.alignment = .fill
        rowsStack.distribution = .fill
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.clipsToBounds = false
        rowsStack.backgroundColor = .clear

        emojiPanel.isHidden = true
        emojiPanel.onSelect = { [weak self] emoji in
            guard let self else { return }
            EmojiCatalog.recordRecent(emoji)
            self.delegate?.keyboardView(self, didTapKey: .character(emoji))
        }

        emojiCategoryBar.onSelectCategory = { [weak self] categoryID in
            self?.emojiPanel.selectCategory(categoryID)
        }

        emojiPanel.onCategoryChange = { [weak self] categoryID in
            self?.emojiCategoryBar.setSelectedCategory(categoryID)
        }

        emojiPanel.onSearchModeChange = { [weak self] active in
            guard let self else { return }
            self.emojiSearchTyping = active
            self.onPreferredHeightChange?()
            self.rebuildKeys()
        }

        addSubview(suggestionBar)
        addSubview(rowsStack)
        addSubview(keyPreview)

        let suggestionHeightConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: suggestionHeight)
        suggestionBarHeightConstraint = suggestionHeightConstraint

        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            suggestionHeightConstraint,

            rowsStack.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: topKeysInset),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: sideInset),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -sideInset),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
        ])
    }

    private func rebuildKeys() {
        releaseActiveKey(commit: false)
        keyPreview.dismiss(animated: false)
        letterKeyEntries.removeAll()
        shiftKeyButton = nil
        keyTargetsCacheValid = false
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if layout == .emoji {
            // Native emoji keyboard hides the prediction strip entirely.
            suggestionBar.isHidden = true
            suggestionBarHeightConstraint?.constant = 0

            emojiPanel.isHidden = false
            emojiSearchTyping = emojiPanel.isSearchActive
            if !emojiSearchTyping {
                emojiPanel.prepareForDisplay()
                emojiCategoryBar.rebuild()
            }
            rowsStack.addArrangedSubview(emojiPanel)

            // Panel takes all space above the bottom bar (and QWERTY when searching).
            let chrome = topKeysInset + bottomInset + bottomRowHeight + rowSpacing
            let lettersBlock: CGFloat = emojiSearchTyping ? 3 * (keyHeight + rowSpacing) : 0
            pinRowHeight(emojiPanel, height: preferredContentHeight - chrome - lettersBlock)

            if emojiSearchTyping {
                for (index, row) in letterRows.enumerated() {
                    let rowView = makeLetterRow(row, rowIndex: index)
                    pinRowHeight(rowView, height: keyHeight)
                    rowsStack.addArrangedSubview(rowView)
                }
            }

            let bottom = makeEmojiBottomRow()
            pinRowHeight(bottom, height: bottomRowHeight)
            rowsStack.addArrangedSubview(bottom)
            return
        }

        suggestionBar.isHidden = false
        suggestionBarHeightConstraint?.constant = suggestionHeight

        emojiSearchTyping = false

        emojiPanel.isHidden = true

        let rows: [[String]]
        switch layout {
        case .letters:
            rows = letterRows
        case .numbers:
            rows = numberRows
        case .symbols:
            rows = symbolRows
        case .emoji:
            rows = []
        }

        for (index, row) in rows.enumerated() {
            let rowView = makeLetterRow(row, rowIndex: index)
            pinRowHeight(rowView, height: keyHeight)
            rowsStack.addArrangedSubview(rowView)
        }
        let bottom = makeBottomRow()
        pinRowHeight(bottom, height: bottomRowHeight)
        rowsStack.addArrangedSubview(bottom)
    }

    private func pinRowHeight(_ row: UIView, height: CGFloat) {
        row.translatesAutoresizingMaskIntoConstraints = false
        let constraint = row.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        row.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private var usesLetterKeyLayout: Bool {
        layout == .letters || (layout == .emoji && emojiSearchTyping)
    }

    private func makeLetterRow(_ characters: [String], rowIndex: Int) -> UIView {
        let letters = UIStackView()
        letters.axis = .horizontal
        letters.spacing = keySpacing
        letters.alignment = .fill
        letters.distribution = .fillEqually
        letters.backgroundColor = .clear

        for raw in characters {
            let insert = insertValue(for: raw)
            let button = KeyButton(style: .letter)
            button.setTitle(displayTitle(for: raw), for: .normal)
            wireKeyPreview(for: button)
            button.onTap = { [weak self] in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .character(insert))
                self.consumeShiftAfterCharacter()
            }
            letterKeyEntries.append((button, raw))
            letters.addArrangedSubview(button)
        }

        if usesLetterKeyLayout, rowIndex == 1 {
            let wrapper = UIStackView()
            wrapper.axis = .horizontal
            wrapper.backgroundColor = .clear
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
            row.backgroundColor = .clear

            if usesLetterKeyLayout {
                let shift = KeyButton(style: .action)
                let symbol = shiftLocked ? "capslock.fill" : (shiftEnabled ? "shift.fill" : "shift")
                shift.setSymbol(systemName: symbol, pointSize: 15)
                if shiftEnabled || shiftLocked {
                    shift.setActionHighlighted(true)
                }
                shift.onTap = { [weak self] in
                    guard let self else { return }
                    self.delegate?.keyboardView(self, didTapKey: .shift)
                }
                shift.widthAnchor.constraint(equalToConstant: 42).isActive = true
                shiftKeyButton = shift
                row.addArrangedSubview(shift)
            } else {
                switch layout {
                case .numbers:
                    let symbols = KeyButton(style: .action)
                    symbols.setTitle("#+=", for: .normal)
                    symbols.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
                    symbols.onTap = { [weak self] in
                        guard let self else { return }
                        self.delegate?.keyboardView(self, didTapKey: .symbolsToggle)
                    }
                    symbols.widthAnchor.constraint(equalToConstant: 42).isActive = true
                    row.addArrangedSubview(symbols)

                case .symbols:
                    let numbers = KeyButton(style: .action)
                    numbers.setTitle("123", for: .normal)
                    numbers.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
                    numbers.onTap = { [weak self] in
                        guard let self else { return }
                        self.delegate?.keyboardView(self, didTapKey: .symbolsToggle)
                    }
                    numbers.widthAnchor.constraint(equalToConstant: 42).isActive = true
                    row.addArrangedSubview(numbers)

                case .letters, .emoji:
                    break
                }
            }

            row.addArrangedSubview(letters)

            let delete = KeyButton(style: .action)
            delete.setSymbol(systemName: "delete.left", pointSize: 16)
            delete.onTap = { [weak self] in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .backspace)
            }
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
        stack.backgroundColor = .clear

        let layoutKey = KeyButton(style: .action)
        let layoutTitle = layout == .letters ? "123" : "ABC"
        layoutKey.setTitle(layoutTitle, for: .normal)
        layoutKey.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        layoutKey.widthAnchor.constraint(equalToConstant: 42).isActive = true
        layoutKey.onTap = { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .layoutToggle)
        }
        stack.addArrangedSubview(layoutKey)

        if showsGlobe {
            let globe = KeyButton(style: .action)
            globe.setSymbol(systemName: "globe", pointSize: 17)
            globe.widthAnchor.constraint(equalToConstant: 42).isActive = true
            globe.onTap = { [weak self] in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTapKey: .globe)
            }
            stack.addArrangedSubview(globe)
        }

        let emoji = KeyButton(style: .action)
        emoji.setEmojiKeyIcon()
        if layout == .emoji {
            emoji.setActionHighlighted(true)
        }
        emoji.widthAnchor.constraint(equalToConstant: 42).isActive = true
        emoji.onTap = { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .emoji)
        }
        stack.addArrangedSubview(emoji)

        let space = KeyButton(style: .space)
        space.setTitle("space", for: .normal)
        space.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        space.setTitleColor(KeyboardPalette.secondaryLabel, for: .normal)
        space.onTap = { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .space)
        }
        stack.addArrangedSubview(space)

        let ret = KeyButton(style: usesBlueReturn ? .returnKey : .action)
        if usesBlueReturn {
            ret.setTitle(returnTitle, for: .normal)
            ret.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        } else {
            ret.setSymbol(systemName: "return.left", pointSize: 17)
        }
        ret.widthAnchor.constraint(equalToConstant: usesBlueReturn ? 88 : 88).isActive = true
        ret.onTap = { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardView(self, didTapKey: .returnKey)
        }
        stack.addArrangedSubview(ret)

        return stack
    }

    /// Native emoji keyboard bottom: plain ABC · category icons (selected in a circle) · plain delete.
    private func makeEmojiBottomRow() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.distribution = .fill
        stack.backgroundColor = .clear

        let abc = UIButton(type: .system)
        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        abc.setTitleColor(KeyboardPalette.label, for: .normal)
        abc.widthAnchor.constraint(equalToConstant: 52).isActive = true
        abc.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.emojiPanel.endSearch()
            self.delegate?.keyboardView(self, didTapKey: .layoutToggle)
        }, for: .touchUpInside)
        stack.addArrangedSubview(abc)

        emojiCategoryBar.translatesAutoresizingMaskIntoConstraints = false
        emojiCategoryBar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(emojiCategoryBar)

        let delete = UIButton(type: .system)
        let deleteConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        delete.setImage(UIImage(systemName: "delete.left", withConfiguration: deleteConfig), for: .normal)
        delete.tintColor = KeyboardPalette.label
        delete.widthAnchor.constraint(equalToConstant: 52).isActive = true
        delete.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.emojiPanel.isSearchActive, self.emojiPanel.deleteSearchCharacter() {
                return
            }
            self.delegate?.keyboardView(self, didTapKey: .backspace)
        }, for: .touchUpInside)
        stack.addArrangedSubview(delete)

        return stack
    }

    /// Native blues the return key for go/search/send/etc.; plain return uses the arrow.
    private var usesBlueReturn: Bool {
        !["return", "default"].contains(returnTitle.lowercased())
    }

    private func displayTitle(for raw: String) -> String {
        guard usesLetterKeyLayout else { return raw }
        if shiftEnabled || shiftLocked {
            return raw.uppercased()
        }
        return raw
    }

    private func insertValue(for raw: String) -> String {
        guard usesLetterKeyLayout else { return raw }
        if shiftEnabled || shiftLocked {
            return raw.uppercased()
        }
        return raw
    }

    private func consumeShiftAfterCharacter() {
        guard usesLetterKeyLayout, shiftEnabled, !shiftLocked else { return }
        shiftEnabled = false
        refreshLetterKeyTitles()
    }

    private func refreshLetterKeyTitles() {
        for entry in letterKeyEntries {
            entry.button.setTitle(displayTitle(for: entry.raw), for: .normal)
        }
        if let shift = shiftKeyButton {
            let symbol = shiftLocked ? "capslock.fill" : (shiftEnabled ? "shift.fill" : "shift")
            shift.setSymbol(systemName: symbol, pointSize: 15)
            shift.setActionHighlighted(shiftEnabled || shiftLocked)
        }
    }

    private func flexibleSpacer(_ width: CGFloat) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
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

// MARK: - Emoji keyboard (native-style)

private enum EmojiChrome {
    static var searchFieldFill: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.24, alpha: 1)
                : UIColor(white: 0.90, alpha: 1)
        }
    }

    static var selectedIcon: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
    }

    static var unselectedIcon: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.45)
                : UIColor.black.withAlphaComponent(0.35)
        }
    }

    static var searchPlaceholder: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.35)
                : UIColor.black.withAlphaComponent(0.30)
        }
    }
}

/// Transparent row of category icons; the selected one sits in a circular highlight (native style).
private final class EmojiCategoryBarView: UIView {
    var onSelectCategory: ((String) -> Void)?

    private var selectedCategoryID = "recent"
    private var buttonsByID: [String: UIButton] = [:]

    private let stack = UIStackView()

    private static var selectionCircle: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.22)
                : UIColor(white: 0, alpha: 0.10)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        stack.axis = .horizontal
        stack.spacing = 0
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func rebuild() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buttonsByID.removeAll()

        for category in EmojiCatalog.displayCategories {
            let button = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            button.setImage(UIImage(systemName: category.icon, withConfiguration: config), for: .normal)
            button.accessibilityLabel = category.name
            button.layer.cornerRadius = 16
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.onSelectCategory?(category.id)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
            buttonsByID[category.id] = button
        }

        applySelection()
    }

    func setSelectedCategory(_ id: String) {
        guard id != selectedCategoryID else { return }
        selectedCategoryID = id
        applySelection()
    }

    private func applySelection() {
        for (id, button) in buttonsByID {
            let selected = id == selectedCategoryID
            button.tintColor = selected ? EmojiChrome.selectedIcon : EmojiChrome.unselectedIcon
            button.backgroundColor = selected ? Self.selectionCircle : .clear
        }
    }
}

private final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate {
    var onSelect: ((String) -> Void)?
    var onCategoryChange: ((String) -> Void)?
    var onSearchModeChange: ((Bool) -> Void)?

    private static let searchHeight: CGFloat = 36

    private var selectedCategoryID = "recent"
    private var searchQuery = ""
    private(set) var isSearchActive = false
    private var searchDebounceTask: Task<Void, Never>?

    /// Sections shown in the horizontally-scrolling grid; cached to avoid re-reading defaults.
    private var sections: [EmojiCategory] = EmojiCatalog.displayCategories
    private var searchResults: [String] = []

    private let searchContainer = UIView()
    private let searchIcon = UIImageView()
    private let searchField = UITextField()

    private lazy var collectionView: UICollectionView = {
        let flow = UICollectionViewFlowLayout()
        // Horizontal flow fills columns top-to-bottom, then moves right — native emoji scroll.
        flow.scrollDirection = .horizontal
        flow.minimumInteritemSpacing = 0
        flow.minimumLineSpacing = 0
        flow.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 12)
        let view = UICollectionView(frame: .zero, collectionViewLayout: flow)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.keyboardDismissMode = .none
        view.dataSource = self
        view.delegate = self
        view.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        return view
    }()

    private var isShowingSearchResults: Bool {
        isSearchActive && !searchQuery.isEmpty
    }

    private func emoji(at indexPath: IndexPath) -> String {
        if isShowingSearchResults {
            guard searchResults.indices.contains(indexPath.item) else { return "" }
            return searchResults[indexPath.item]
        }
        guard sections.indices.contains(indexPath.section) else { return "" }
        let characters = sections[indexPath.section].characters
        guard characters.indices.contains(indexPath.item) else { return "" }
        return characters[indexPath.item]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        // Native emoji search: fully-rounded pill with muted icon + placeholder.
        searchContainer.backgroundColor = EmojiChrome.searchFieldFill
        searchContainer.layer.cornerRadius = Self.searchHeight / 2
        searchContainer.layer.cornerCurve = .continuous
        searchContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        searchIcon.image = UIImage(systemName: "magnifyingglass", withConfiguration: iconConfig)
        searchIcon.tintColor = EmojiChrome.searchPlaceholder
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        searchField.delegate = self
        searchField.borderStyle = .none
        searchField.backgroundColor = .clear
        searchField.font = .systemFont(ofSize: 17)
        searchField.textColor = KeyboardPalette.label
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search Emoji",
            attributes: [.foregroundColor: EmojiChrome.searchPlaceholder]
        )
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.spellCheckingType = .no
        searchField.returnKeyType = .done
        searchField.inputView = UIView(frame: .zero)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(activateSearch))
        searchContainer.addGestureRecognizer(tap)

        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchContainer)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: topAnchor),
            searchContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchContainer.heightAnchor.constraint(equalToConstant: Self.searchHeight),

            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor),

            collectionView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForDisplay() {
        searchDebounceTask?.cancel()
        isSearchActive = false
        searchQuery = ""
        searchResults = []
        searchField.text = ""
        searchField.resignFirstResponder()
        sections = EmojiCatalog.displayCategories
        selectedCategoryID = sections.first?.id ?? "smileys"
        onCategoryChange?(selectedCategoryID)
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
    }

    func selectCategory(_ id: String) {
        if isSearchActive {
            endSearch()
        }
        guard let sectionIndex = sections.firstIndex(where: { $0.id == id }),
              !sections[sectionIndex].emojis.isEmpty else { return }
        selectedCategoryID = id
        onCategoryChange?(id)
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: sectionIndex),
            at: .left,
            animated: true
        )
    }

    /// Tracks the leftmost visible section while the user swipes; keeps the bar in sync.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView, !isShowingSearchResults else { return }
        let probe = CGPoint(
            x: collectionView.contentOffset.x + 20,
            y: collectionView.bounds.height / 2
        )
        guard let indexPath = collectionView.indexPathForItem(at: probe),
              indexPath.section < sections.count else { return }
        let id = sections[indexPath.section].id
        guard id != selectedCategoryID else { return }
        selectedCategoryID = id
        onCategoryChange?(id)
    }

    @discardableResult
    func insertSearchCharacter(_ value: String) -> Bool {
        guard isSearchActive else { return false }
        searchField.insertText(value)
        syncSearchFromField()
        return true
    }

    @discardableResult
    func deleteSearchCharacter() -> Bool {
        guard isSearchActive else { return false }
        if !(searchField.text?.isEmpty ?? true) {
            searchField.deleteBackward()
            syncSearchFromField()
            return true
        }
        return false
    }

    func endSearch() {
        searchDebounceTask?.cancel()
        let wasActive = isSearchActive
        isSearchActive = false
        searchQuery = ""
        searchResults = []
        searchField.text = ""
        searchField.resignFirstResponder()
        collectionView.reloadData()
        if wasActive {
            onSearchModeChange?(false)
        }
    }

    @objc private func activateSearch() {
        guard !isSearchActive else { return }
        isSearchActive = true
        onSearchModeChange?(true)
        searchField.becomeFirstResponder()
    }

    private func syncSearchFromField() {
        let query = searchField.text ?? ""
        searchQuery = query
        searchDebounceTask?.cancel()

        guard !query.isEmpty else {
            searchResults = []
            collectionView.reloadData()
            collectionView.setContentOffset(.zero, animated: false)
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let latest = self.searchField.text ?? ""
            guard latest == query else { return }
            self.searchResults = EmojiCatalog.search(latest)
            self.isSearchActive = true
            self.collectionView.reloadData()
            self.collectionView.setContentOffset(.zero, animated: false)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        endSearch()
        return true
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        isShowingSearchResults ? 1 : sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isShowingSearchResults {
            return searchResults.count
        }
        return sections[section].emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: indexPath)
        if let emojiCell = cell as? EmojiCell {
            emojiCell.configure(emoji: emoji(at: indexPath))
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(emoji(at: indexPath))
    }

    /// Square cells sized so full rows fill the grid height (native: ~3 large rows).
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let rows: CGFloat = 3
        let side = floor(collectionView.bounds.height / rows)
        return CGSize(width: side, height: side)
    }
}

private final class EmojiCell: UICollectionViewCell {
    static let reuseID = "EmojiCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 1),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: String) {
        label.text = emoji
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.alpha = isHighlighted ? 0.5 : 1
            contentView.transform = isHighlighted
                ? CGAffineTransform(scaleX: 0.92, y: 0.92)
                : .identity
        }
    }
}

// MARK: - Predictive strip (no plate — floats on system keyboard chrome)

/// Orbiting dots — "AI thinking" indicator for the suggestion strip.
final class AITranslatingIndicatorView: UIView {
    private static let orbitRadius: CGFloat = 7
    private static let particleSize: CGFloat = 5
    private static let orbitDuration: CFTimeInterval = 1.1

    private let particles: [UIView] = (0..<3).map { _ in UIView() }
    private var isAnimating = false
    private var lastOrbitBounds: CGSize = .zero

    private let particleColors: [UIColor] = [
        UIColor(red: 0.22, green: 0.52, blue: 1.0, alpha: 1),
        UIColor(red: 0.12, green: 0.78, blue: 0.88, alpha: 1),
        UIColor(red: 0.50, green: 0.38, blue: 0.98, alpha: 1),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        for (index, particle) in particles.enumerated() {
            particle.backgroundColor = particleColors[index]
            particle.layer.cornerRadius = Self.particleSize / 2
            addSubview(particle)
        }

        stopAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 24, height: 20)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 4, bounds.height > 4 else { return }

        layoutParticlesOnOrbit()

        if isAnimating, bounds.size != lastOrbitBounds {
            lastOrbitBounds = bounds.size
            applyOrbitAnimations()
        }
    }

    func refreshColors() {
        for (index, particle) in particles.enumerated() {
            particle.backgroundColor = particleColors[index]
        }
    }

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        isHidden = false
        alpha = 1
        particles.forEach {
            $0.alpha = 1
            $0.transform = .identity
        }

        lastOrbitBounds = .zero
        setNeedsLayout()
        layoutIfNeeded()

        if bounds.width > 4 {
            layoutParticlesOnOrbit()
            lastOrbitBounds = bounds.size
            applyOrbitAnimations()
        }
    }

    func stopAnimating() {
        isAnimating = false
        lastOrbitBounds = .zero
        particles.forEach {
            $0.layer.removeAllAnimations()
            $0.alpha = 0.4
            $0.transform = .identity
        }
    }

    func playCompletionBurst() {
        particles.forEach { $0.layer.removeAllAnimations() }
        layoutParticlesOnOrbit()

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            for particle in self.particles {
                particle.transform = CGAffineTransform(scaleX: 0.15, y: 0.15)
                particle.alpha = 0
            }
        }
    }

    private func layoutParticlesOnOrbit() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (index, particle) in particles.enumerated() {
            let angle = (CGFloat(index) / CGFloat(particles.count)) * 2 * .pi - .pi / 2
            let x = center.x + cos(angle) * Self.orbitRadius
            let y = center.y + sin(angle) * Self.orbitRadius
            particle.bounds = CGRect(x: 0, y: 0, width: Self.particleSize, height: Self.particleSize)
            particle.center = CGPoint(x: x, y: y)
        }
    }

    private func applyOrbitAnimations() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (index, particle) in particles.enumerated() {
            particle.layer.removeAnimation(forKey: "orbit")
            particle.layer.removeAnimation(forKey: "pulse")
            particle.layer.removeAnimation(forKey: "fade")

            let startAngle = (CGFloat(index) / CGFloat(particles.count)) * 2 * .pi - .pi / 2
            let path = UIBezierPath(
                arcCenter: center,
                radius: Self.orbitRadius,
                startAngle: startAngle,
                endAngle: startAngle + 2 * .pi,
                clockwise: true
            )

            let orbit = CAKeyframeAnimation(keyPath: "position")
            orbit.path = path.cgPath
            orbit.duration = Self.orbitDuration
            orbit.repeatCount = .infinity
            orbit.calculationMode = .paced
            orbit.isRemovedOnCompletion = false
            orbit.timeOffset = Double(index) * (Self.orbitDuration / Double(particles.count))

            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.7
            pulse.toValue = 1.15
            pulse.duration = Self.orbitDuration * 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.timeOffset = Double(index) * 0.12
            pulse.isRemovedOnCompletion = false

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.55
            fade.toValue = 1.0
            fade.duration = Self.orbitDuration * 0.5
            fade.autoreverses = true
            fade.repeatCount = .infinity
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fade.timeOffset = Double(index) * 0.12
            fade.isRemovedOnCompletion = false

            particle.layer.add(orbit, forKey: "orbit")
            particle.layer.add(pulse, forKey: "pulse")
            particle.layer.add(fade, forKey: "fade")
        }
    }
}

final class SuggestionBarView: UIView, UIGestureRecognizerDelegate {
    var onTapAccept: (() -> Void)?
    var onToggleTranslations: (() -> Void)?
    var onCycleTone: (() -> Void)?

    private enum Metrics {
        static let iconTapSize: CGFloat = 30
        static let iconPointSize: CGFloat = 15
        static let sideInset: CGFloat = 14
    }

    private let contentStack = UIStackView()
    private let aiIndicator = AITranslatingIndicatorView()
    private let label = UILabel()
    private let toneButton = UIButton(type: .system)
    private let toggleButton = UIButton(type: .system)
    private let acceptTap = UITapGestureRecognizer()
    private var canAccept = false
    private var displayedState: TranslationSuggester.SuggestionState = .idle
    private var animationGeneration = 0
    private var isShowingLoading = false
    private var isShowingToneHint = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        backgroundColor = .clear
        isOpaque = false

        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textAlignment = .center
        label.textColor = KeyboardPalette.label
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.numberOfLines = 1

        aiIndicator.setContentHuggingPriority(.required, for: .horizontal)
        aiIndicator.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 7
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(aiIndicator)
        contentStack.addArrangedSubview(label)

        toneButton.translatesAutoresizingMaskIntoConstraints = false
        toneButton.addTarget(self, action: #selector(handleToneCycle), for: .touchUpInside)
        updateToneAppearance()

        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.addTarget(self, action: #selector(handleToggle), for: .touchUpInside)
        updateToggleAppearance()

        addSubview(toneButton)
        addSubview(contentStack)
        addSubview(toggleButton)

        let iconSize = Metrics.iconTapSize
        NSLayoutConstraint.activate([
            toneButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.sideInset),
            toneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            toneButton.widthAnchor.constraint(equalToConstant: iconSize),
            toneButton.heightAnchor.constraint(equalToConstant: iconSize),

            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.sideInset),
            toggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: iconSize),
            toggleButton.heightAnchor.constraint(equalToConstant: iconSize),

            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: toneButton.trailingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: toggleButton.leadingAnchor, constant: -8),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        acceptTap.addTarget(self, action: #selector(handleTap))
        acceptTap.delegate = self
        addGestureRecognizer(acceptTap)
        apply(.idle, animated: false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Let circle icon buttons handle their own taps — avoid accept + tone/toggle racing.
        touch.view is UIButton ? false : true
    }

    private func beginAnimation() -> Int {
        animationGeneration += 1
        label.layer.removeAllAnimations()
        label.layer.mask = nil
        aiIndicator.layer.removeAllAnimations()
        return animationGeneration
    }

    private func ensureContentVisible() {
        label.layer.mask = nil
        label.alpha = 1
        label.transform = .identity
    }

    private func isCurrentAnimation(_ generation: Int) -> Bool {
        generation == animationGeneration
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshColors() {
        backgroundColor = .clear
        aiIndicator.refreshColors()
        updateToggleAppearance()
        updateToneAppearance()
    }

    func syncToggleState() {
        updateToggleAppearance()
        render(displayedState)
        ensureContentVisible()
    }

    func syncToneState() {
        updateToneAppearance()
    }

    func apply(_ state: TranslationSuggester.SuggestionState) {
        apply(state, animated: state != displayedState)
    }

    private func apply(_ state: TranslationSuggester.SuggestionState, animated: Bool) {
        if isShowingToneHint {
            displayedState = state
            return
        }

        if isLoadingPhraseUpdate(from: displayedState, to: state) {
            displayedState = state
            return
        }

        let stateChanged = state != displayedState
        let previousState = displayedState
        displayedState = state

        let shouldAnimate = animated && stateChanged && state != .idle
        guard shouldAnimate else {
            _ = beginAnimation()
            render(state)
            ensureContentVisible()
            return
        }

        let generation = beginAnimation()
        let playBurst = isTranslationReveal(from: previousState, to: state)

        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) { [weak self] in
            guard let self, self.isCurrentAnimation(generation) else { return }
            self.label.alpha = 0
            if case .loading = previousState {
                self.aiIndicator.alpha = 0
            }
        } completion: { [weak self] finished in
            guard let self else { return }
            guard finished, self.isCurrentAnimation(generation) else {
                self.render(state)
                self.ensureContentVisible()
                return
            }

            if playBurst {
                self.aiIndicator.playCompletionBurst()
            }

            self.render(state)
            self.label.alpha = 0
            let enteringLoading = if case .loading = state { true } else { false }
            if enteringLoading {
                self.aiIndicator.alpha = 0
            }

            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) { [weak self] in
                guard let self, self.isCurrentAnimation(generation) else { return }
                self.ensureContentVisible()
                if enteringLoading {
                    self.aiIndicator.alpha = 1
                }
            } completion: { [weak self] _ in
                guard let self, self.isCurrentAnimation(generation) else { return }
                if enteringLoading {
                    self.aiIndicator.startAnimating()
                }
            }
        }
    }

    private func isLoadingPhraseUpdate(
        from previous: TranslationSuggester.SuggestionState,
        to next: TranslationSuggester.SuggestionState
    ) -> Bool {
        guard case .loading(let prevPhrase, _) = previous,
              case .loading(let nextPhrase, _) = next else { return false }
        return prevPhrase != nextPhrase
    }

    private func isTranslationReveal(
        from previous: TranslationSuggester.SuggestionState,
        to next: TranslationSuggester.SuggestionState
    ) -> Bool {
        if case .loading = previous, case .ready = next { return true }
        return false
    }

    private func render(_ state: TranslationSuggester.SuggestionState) {
        canAccept = false
        label.textColor = KeyboardPalette.label
        label.font = .systemFont(ofSize: 17, weight: .regular)

        let wasLoading = isShowingLoading
        let isLoading: Bool
        if case .loading = state { isLoading = true } else { isLoading = false }
        isShowingLoading = isLoading

        if wasLoading && !isLoading {
            aiIndicator.stopAnimating()
            aiIndicator.isHidden = true
        }

        switch state {
        case .idle:
            aiIndicator.isHidden = true
            aiIndicator.stopAnimating()
            if KeyboardStatusStore.translationsEnabled {
                label.text = "Type Singlish — tap suggestion for English"
            } else {
                label.text = "Translations off — normal keyboard"
            }
            label.textColor = KeyboardPalette.tertiaryLabel
            label.font = .systemFont(ofSize: 14, weight: .regular)

        case .needsFullAccess:
            aiIndicator.isHidden = true
            aiIndicator.stopAnimating()
            label.text = "Turn on Full Access to translate"
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 15, weight: .regular)

        case .loading:
            aiIndicator.isHidden = false
            aiIndicator.alpha = 1
            if !wasLoading {
                aiIndicator.startAnimating()
            }
            label.text = "Translating"
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 15, weight: .medium)

        case .ready(_, _, let translation):
            aiIndicator.isHidden = true
            aiIndicator.stopAnimating()
            canAccept = true
            label.text = translation.translation

        case .failed(_, _, let message):
            aiIndicator.isHidden = true
            aiIndicator.stopAnimating()
            label.text = Self.friendlyFailureMessage(message)
            label.textColor = KeyboardPalette.secondaryLabel
            label.font = .systemFont(ofSize: 14, weight: .regular)
        }
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

    @objc private func handleToggle() {
        KeyboardStatusStore.translationsEnabled.toggle()
        updateToggleAppearance()
        onToggleTranslations?()
    }

    @objc private func handleToneCycle() {
        KeyboardStatusStore.translationTone = KeyboardStatusStore.translationTone.next
        updateToneAppearance()
        showToneModeHint()
        onCycleTone?()
    }

    func showToneModeHint() {
        isShowingToneHint = true

        aiIndicator.isHidden = true
        aiIndicator.stopAnimating()

        let tone = KeyboardStatusStore.translationTone
        label.text = tone.modeHint
        label.textColor = KeyboardPalette.secondaryLabel
        label.font = .systemFont(ofSize: 15, weight: .semibold)

        ensureContentVisible()
        label.alpha = 0
        label.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction]
        ) {
            self.label.alpha = 1
            self.label.transform = .identity
        }
    }

    func endToneModeHint() {
        guard isShowingToneHint else { return }
        isShowingToneHint = false
        apply(displayedState, animated: false)
    }

    private func updateToneAppearance() {
        let tone = KeyboardStatusStore.translationTone
        let config = UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .medium)
        toneButton.setImage(UIImage(systemName: tone.systemImage, withConfiguration: config), for: .normal)
        toneButton.tintColor = KeyboardPalette.secondaryLabel
        toneButton.accessibilityLabel = "Tone: \(tone.label). Double tap to change."
    }

    private func updateToggleAppearance() {
        let enabled = KeyboardStatusStore.translationsEnabled
        let symbol = enabled ? "character.bubble.fill" : "character.bubble"
        let config = UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .medium)
        toggleButton.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        toggleButton.tintColor = enabled ? .systemGreen : KeyboardPalette.tertiaryLabel
        toggleButton.accessibilityLabel = enabled ? "Translations on" : "Translations off"
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

    var onTap: (() -> Void)?
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

    /// Native emoji key uses the filled inverse smiley on light keyboards.
    func setEmojiKeyIcon() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let symbol = isDark ? "face.smiling" : "face.smiling.inverse"
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        setTitle(nil, for: .normal)
        tintColor = isDark ? KeyboardPalette.label : UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyChrome()
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

    func setPressed(_ pressed: Bool) {
        if pressed {
            applyPressedAppearance()
            if style == .letter {
                onBeginPreview?()
            }
        } else {
            restoreAppearance()
            if style == .letter {
                onEndPreview?()
            }
        }
    }

    private func configures() {
        isUserInteractionEnabled = false
        titleLabel?.font = .systemFont(
            ofSize: style == .letter ? 22 : 16,
            weight: style == .letter ? .regular : .medium
        )
        setTitleColor(style == .returnKey ? .white : KeyboardPalette.label, for: .normal)
        backgroundColor = styleBackground
        layer.cornerRadius = 7
        layer.masksToBounds = false
        applyChrome()
    }

    private func applyChrome() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        if isDark {
            layer.shadowOpacity = 0
            layer.borderWidth = 0
        } else {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.10
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 0.5
            layer.borderWidth = 0.5
            layer.borderColor = UIColor(white: 0, alpha: 0.06).cgColor
        }
        layer.cornerRadius = 7
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

    private func applyPressedAppearance() {
        switch style {
        case .letter:
            backgroundColor = KeyboardPalette.pressedKey
        case .space:
            backgroundColor = KeyboardPalette.pressedKey
        case .action:
            backgroundColor = KeyboardPalette.pressedActionKey
        case .returnKey:
            backgroundColor = KeyboardPalette.pressedReturnKey
        }
    }

    private func restoreAppearance() {
        backgroundColor = styleBackground
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
    /// Letter + space keys — solid white on light so they read on white app backgrounds.
    static var key: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.28)
                : UIColor(white: 1, alpha: 1.0)
        }
    }

    /// Pressed letter/space — visible gray on light, brighter on dark.
    static var pressedKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.42)
                : UIColor(red: 0.74, green: 0.77, blue: 0.82, alpha: 1)
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

    /// Shift, 123, emoji, delete — darker gray plate on light (native action keys).
    static var actionKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.20)
                : UIColor(red: 0.72, green: 0.75, blue: 0.80, alpha: 1)
        }
    }

    static var pressedActionKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.32)
                : UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1)
        }
    }

    static var returnKey: UIColor { .systemBlue }

    static var pressedReturnKey: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.systemBlue.withAlphaComponent(0.85)
                : UIColor(red: 0, green: 0.40, blue: 0.88, alpha: 1)
        }
    }

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
