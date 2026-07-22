import SwiftUI
import UIKit

struct ContentView: View {
    @State private var viewModel = TranslationViewModel()
    @FocusState private var inputFocused: Bool
    @AppStorage("keyboardSetupExpanded") private var keyboardSetupExpanded = true
    @State private var isNavScrolled = false
    @State private var scrollTarget: String?
    @State private var keyboardIsReady = KeyboardStatusStore.isReady
    @State private var keyboardLastActive = KeyboardStatusStore.lastActiveAt
    @State private var selectedTone = KeyboardStatusStore.translationTone

    var body: some View {
        ZStack {
            SayWellTheme.canvas
                .ignoresSafeArea()
            AtmosphereBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        heroSection
                        inputSection
                        toneSection
                        actionRow
                        resultSection
                            .id("result")
                        if !viewModel.isLoading {
                            examplesSection
                        }
                        if !viewModel.recentHistory.isEmpty {
                            RecentTranslationsSection(
                                entries: viewModel.recentHistory,
                                onSelect: { entry in
                                    inputFocused = false
                                    viewModel.useHistoryEntry(entry)
                                    Task { await viewModel.translate() }
                                },
                                onClear: viewModel.clearHistory
                            )
                        }
                        if viewModel.cachedPhraseCount > 0 {
                            cachedPhrasesSection
                        }
                        if viewModel.commonPhrasesCount > 0 {
                            commonPhrasesSection
                        }
                        keyboardSetupSection
                            .id("keyboard")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 36)
                    .background(ScrollOffsetTracker())
                }
                .coordinateSpace(name: "saywellScroll")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    let scrolled = offset < -12
                    if scrolled != isNavScrolled {
                        isNavScrolled = scrolled
                    }
                }
                .onChange(of: viewModel.scrollToken) { _, _ in
                    guard viewModel.scrollToken != "welcome" else { return }
                    scrollTarget = "result"
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    scrollTarget = nil
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FloatingNavBar(
                isScrolled: isNavScrolled,
                hasInput: !viewModel.inputText.isEmpty,
                onClear: {
                    viewModel.clear()
                    inputFocused = true
                },
                onKeyboard: {
                    keyboardSetupExpanded = true
                    scrollTarget = "keyboard"
                },
                onSettings: openSettings
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.phase)
        .onAppear {
            refreshKeyboardStatus()
            // Sync common phrases on app launch (background, non-blocking)
            Task {
                _ = await viewModel.syncCommonPhrases()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshKeyboardStatus()
            selectedTone = KeyboardStatusStore.translationTone
        }
    }

    private func refreshKeyboardStatus() {
        keyboardIsReady = KeyboardStatusStore.isReady
        keyboardLastActive = KeyboardStatusStore.lastActiveAt
    }

    private var heroSection: some View {
        Text("Type in Singlish. Say it well in English.")
            .font(.system(.title3, design: .serif))
            .foregroundStyle(SayWellTheme.lagoon.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Singlish")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon)
                Spacer()
                if !viewModel.inputText.isEmpty {
                    Button("Clear") { viewModel.clear() }
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(SayWellTheme.lagoon.opacity(0.8))
                }
            }

            TextField(
                "",
                text: $viewModel.inputText,
                prompt: Text("mn gedr ynawa")
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.35)),
                axis: .vertical
            )
            .font(.system(.title3, design: .rounded))
            .foregroundStyle(SayWellTheme.ink)
            .lineLimit(3...7)
            .focused($inputFocused)
            .submitLabel(.go)
            .onSubmit {
                Task { await viewModel.translate() }
            }
            .padding(16)
            .background(SayWellTheme.foam.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        inputFocused
                            ? SayWellTheme.brand.opacity(0.55)
                            : SayWellTheme.lagoon.opacity(0.12),
                        lineWidth: inputFocused ? 1.5 : 1
                    )
            }
            .animation(.easeInOut(duration: 0.2), value: inputFocused)

            HStack {
                Text("\(viewModel.characterCount)/\(SayWellAPI.maxInputChars)")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(
                        viewModel.isOverLimit ? SayWellTheme.coral : SayWellTheme.lagoon.opacity(0.55)
                    )
                Spacer()
                Text("Romanized Sinhala")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.45))
            }
        }
    }

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tone")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(SayWellTheme.lagoon)

            HStack(spacing: 8) {
                ForEach(TranslationTone.allCases) { tone in
                    Button {
                        let shouldRetranslate = selectedTone != tone
                            && viewModel.translation != nil
                            && !viewModel.trimmedInput.isEmpty
                        selectedTone = tone
                        KeyboardStatusStore.translationTone = tone
                        if shouldRetranslate {
                            Task { await viewModel.translate() }
                        }
                    } label: {
                        Label(tone.label, systemImage: tone.systemImage)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(selectedTone == tone ? SayWellTheme.ink : SayWellTheme.lagoon.opacity(0.8))
                            .background(
                                selectedTone == tone
                                    ? SayWellTheme.brand.opacity(0.14)
                                    : SayWellTheme.foam.opacity(0.9),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        selectedTone == tone
                                            ? SayWellTheme.brand.opacity(0.45)
                                            : SayWellTheme.lagoon.opacity(0.12),
                                        lineWidth: selectedTone == tone ? 1.5 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTone == tone ? .isSelected : [])
                }
            }

            Text(selectedTone.description)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(SayWellTheme.lagoon.opacity(0.55))
        }
    }

    private var actionRow: some View {
        Button {
            inputFocused = false
            Task { await viewModel.translate() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isLoading {
                    AnimatedDotsView(color: .white.opacity(0.95), dotSize: 4)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                Text(viewModel.isLoading ? loadingButtonTitle : "Translate")
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                viewModel.canTranslate || viewModel.isLoading
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [SayWellTheme.brand, SayWellTheme.lagoon],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    : AnyShapeStyle(SayWellTheme.lagoon.opacity(0.35)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .disabled(viewModel.isLoading || !viewModel.canTranslate)
        .animation(.easeInOut(duration: 0.18), value: viewModel.canTranslate)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isLoading)
    }

    private var loadingButtonTitle: String {
        let phrase = viewModel.trimmedInput
        if phrase.count <= 18 {
            return "Translating…"
        }
        return "Finding English…"
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.phase {
        case .welcome:
            TranslationWelcomeCard()
                .transition(.opacity.combined(with: .move(edge: .bottom)))

        case .loading(let phrase):
            TranslationLoadingCard(phrase: phrase)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

        case .failure(let message):
            VStack(alignment: .leading, spacing: 12) {
                ResultPanel(
                    title: "Couldn't translate",
                    bodyText: message,
                    style: .error
                )

                Button {
                    Task { await viewModel.retry() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(SayWellTheme.brand)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))

        case .success:
            if let translation = viewModel.translation {
                VStack(alignment: .leading, spacing: 14) {
                    ResultPanel(
                        title: "English",
                        bodyText: translation.translation,
                        style: .success,
                        trailing: {
                            HStack(spacing: 8) {
                                TranslationSourceBadge(source: translation.source)
                                ShareLink(item: translation.translation) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.system(.caption, design: .rounded).weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(SayWellTheme.brand)
                                .controlSize(.small)

                                Button {
                                    viewModel.copyTranslation()
                                } label: {
                                    Label(
                                        viewModel.didCopy ? "Copied" : "Copy",
                                        systemImage: viewModel.didCopy ? "checkmark" : "doc.on.doc"
                                    )
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(SayWellTheme.brand)
                                .controlSize(.small)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.didCopy)
                            }
                        }
                    )

                    let trimmed = viewModel.trimmedInput.lowercased()
                    if translation.normalized != trimmed {
                        ResultPanel(
                            title: "Normalized spelling",
                            bodyText: translation.normalized,
                            style: .neutral
                        )
                    }

                    Button {
                        viewModel.clear()
                        inputFocused = true
                    } label: {
                        Label("Translate another", systemImage: "plus.bubble")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(SayWellTheme.lagoon)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try an example")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(SayWellTheme.lagoon.opacity(0.75))

            FlowLayout(spacing: 8) {
                ForEach(ExamplePhrase.allCases) { example in
                    Button(example.label) {
                        inputFocused = false
                        viewModel.useExample(example.text)
                        Task { await viewModel.translate() }
                    }
                    .buttonStyle(ExampleChipStyle())
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .padding(.top, 4)
    }

    private var cachedPhrasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cached phrases")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.65))
                Spacer()
                Text("\(viewModel.cachedPhraseCount)")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.55))
                Button("Clear", action: viewModel.clearLocalPhraseCache)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.7))
            }
        }
        .padding(.top, -20)
    }

    private var commonPhrasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Common phrases (offline)")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(SayWellTheme.lagoon.opacity(0.65))
                    if let lastDownloaded = viewModel.commonPhrasesLastDownloaded {
                        Text("Updated: \(lastDownloaded.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(SayWellTheme.lagoon.opacity(0.4))
                    }
                }
                Spacer()
                Text("\(viewModel.commonPhrasesCount)")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.55))
                Button("Refresh") {
                    Task {
                        _ = await viewModel.syncCommonPhrases()
                    }
                }
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(SayWellTheme.lagoon.opacity(0.7))
                Button("Clear", action: viewModel.clearCommonPhrases)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.7))
            }
        }
        .padding(.top, -20)
    }

    private var keyboardSetupSection: some View {
        Group {
            if keyboardIsReady {
                KeyboardReadyCard(lastActive: keyboardLastActive)
            } else {
                KeyboardSetupCard(
                    isExpanded: $keyboardSetupExpanded,
                    onOpenSettings: openSettings
                )
            }
        }
    }
}

// MARK: - Examples

private enum ExamplePhrase: String, CaseIterable, Identifiable {
    case home
    case meeting
    case thanks
    case notGoing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Going home"
        case .meeting: "Postpone meeting"
        case .thanks: "Thank you"
        case .notGoing: "Not going to work"
        }
    }

    var text: String {
        switch self {
        case .home: "mn gedr ynawa"
        case .meeting: "machan meeting eka postpone karamu"
        case .thanks: "stuti"
        case .notGoing: "mama ada wadata yanne na"
        }
    }
}

// MARK: - Panels

private struct ResultPanel<Trailing: View>: View {
    enum Style { case success, error, neutral }

    let title: String
    let bodyText: String
    let style: Style
    var trailing: (() -> Trailing)?

    init(
        title: String,
        bodyText: String,
        style: Style,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.bodyText = bodyText
        self.style = style
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(style == .error ? SayWellTheme.coral : SayWellTheme.lagoon.opacity(0.7))
                Spacer()
                trailing?()
            }

            Text(bodyText)
                .font(
                    style == .success
                        ? .system(.title3, design: .serif).weight(.medium)
                        : .system(.body, design: .rounded)
                )
                .foregroundStyle(style == .error ? SayWellTheme.coral : SayWellTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(18)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .success: Color("CardSuccess")
        case .error: Color("CardError")
        case .neutral: SayWellTheme.foam.opacity(0.75)
        }
    }

    private var borderColor: Color {
        switch style {
        case .success: SayWellTheme.brand.opacity(0.22)
        case .error: SayWellTheme.coral.opacity(0.25)
        case .neutral: SayWellTheme.lagoon.opacity(0.1)
        }
    }
}

extension ResultPanel where Trailing == EmptyView {
    init(title: String, bodyText: String, style: Style) {
        self.init(title: title, bodyText: bodyText, style: style, trailing: { EmptyView() })
    }
}

private struct ExampleChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(SayWellTheme.ink)
            .background(
                configuration.isPressed
                    ? SayWellTheme.brand.opacity(0.16)
                    : SayWellTheme.foam.opacity(0.9),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(SayWellTheme.lagoon.opacity(0.14), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Atmosphere

private struct AtmosphereBackdrop: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(SayWellTheme.brand.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: -120, y: -220)

            Circle()
                .fill(SayWellTheme.lagoon.opacity(0.1))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(x: 140, y: 320)
        }
    }
}

/// Simple horizontal flow layout for example chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight), positions)
    }
}

#Preview {
    ContentView()
}
