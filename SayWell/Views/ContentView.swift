import SwiftUI
import UIKit

struct ContentView: View {
    @State private var viewModel = TranslationViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            SayWellTheme.canvas
                .ignoresSafeArea()
            AtmosphereBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    brandHeader
                    inputSection
                    actionRow
                    resultSection
                    examplesSection
                    keyboardSetupSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.light)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SayWell")
                .font(SayWellTheme.brandMark)
                .foregroundStyle(SayWellTheme.ink)
                .accessibilityAddTraits(.isHeader)

            Text("Type in Singlish. Say it well in English.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(SayWellTheme.lagoon.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
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

    private var actionRow: some View {
        Button {
            inputFocused = false
            Task { await viewModel.translate() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                Text(viewModel.isLoading ? "Translating…" : "Translate")
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                viewModel.canTranslate
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
        .disabled(!viewModel.canTranslate)
        .animation(.easeInOut(duration: 0.18), value: viewModel.canTranslate)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isLoading)
    }

    @ViewBuilder
    private var resultSection: some View {
        if let errorMessage = viewModel.errorMessage {
            ResultPanel(
                title: "Couldn't translate",
                bodyText: errorMessage,
                style: .error
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if let translation = viewModel.translation {
            VStack(alignment: .leading, spacing: 14) {
                ResultPanel(
                    title: "English",
                    bodyText: translation.translation,
                    style: .success,
                    trailing: {
                        HStack(spacing: 8) {
                            SourceBadge(source: translation.source)
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
                        }
                    }
                )

                let trimmed = viewModel.trimmedInput.lowercased()
                if translation.normalized != trimmed {
                    ResultPanel(
                        title: "Normalized",
                        bodyText: translation.normalized,
                        style: .neutral
                    )
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                        viewModel.useExample(example.text)
                        Task { await viewModel.translate() }
                    }
                    .buttonStyle(ExampleChipStyle())
                }
            }
        }
        .padding(.top, 4)
    }

    private var keyboardSetupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(SayWellTheme.lagoon.opacity(0.75))

            VStack(alignment: .leading, spacing: 12) {
                Text("Enable SayWell Keyboard")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.ink)

                VStack(alignment: .leading, spacing: 8) {
                    setupStep(number: 1, text: "Open Settings → General → Keyboard → Keyboards")
                    setupStep(number: 2, text: "Tap Add New Keyboard… → SayWell")
                    setupStep(number: 3, text: "Tap SayWell → turn on Allow Full Access")
                    setupStep(number: 4, text: "In any app, tap 🌐 to switch to SayWell")
                }

                Text("Full Access is required so the keyboard can call the translation API. iOS will show Apple’s network-access prompt — that’s expected.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(SayWellTheme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
            .background(SayWellTheme.foam.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SayWellTheme.lagoon.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func setupStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(SayWellTheme.brand, in: Circle())
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(SayWellTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
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

private struct SourceBadge: View {
    let source: TranslationSource

    var body: some View {
        Text(source == .cache ? "Cached" : "Live")
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (source == .cache ? SayWellTheme.brand : Color.orange).opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(source == .cache ? SayWellTheme.brand : .orange)
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
