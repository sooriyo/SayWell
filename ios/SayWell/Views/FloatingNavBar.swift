import SwiftUI

struct FloatingNavBar: View {
    var isScrolled: Bool
    var hasInput: Bool
    var onClear: () -> Void
    var onKeyboard: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SayWell")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(SayWellTheme.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("Singlish → English")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.78))
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if hasInput {
                    NavIconButton(
                        systemName: "xmark",
                        accessibilityLabel: "Clear text"
                    ) {
                        onClear()
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                NavIconButton(
                    systemName: "keyboard",
                    accessibilityLabel: "Keyboard setup"
                ) {
                    onKeyboard()
                }

                NavIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Open Settings"
                ) {
                    onSettings()
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: hasInput)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(SayWellTheme.foam.opacity(0.55))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    SayWellTheme.lagoon.opacity(isScrolled ? 0.16 : 0.1),
                    lineWidth: 1
                )
        }
        .shadow(
            color: SayWellTheme.ink.opacity(isScrolled ? 0.1 : 0.06),
            radius: isScrolled ? 18 : 12,
            y: isScrolled ? 10 : 6
        )
        .animation(.easeOut(duration: 0.22), value: isScrolled)
    }
}

private struct NavIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SayWellTheme.lagoon)
                .frame(width: 36, height: 36)
                .background(SayWellTheme.brand.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Scroll offset

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollOffsetTracker: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: geometry.frame(in: .named("saywellScroll")).minY
            )
        }
        .frame(height: 0)
    }
}
