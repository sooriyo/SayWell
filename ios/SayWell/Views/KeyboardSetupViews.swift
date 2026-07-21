import SwiftUI

struct KeyboardReadyCard: View {
    let lastActive: Date?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(SayWellTheme.brand)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard is ready")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.ink)

                Text(subtitle)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color("CardSuccess").opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SayWellTheme.brand.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SayWell keyboard is enabled with Full Access")
    }

    private var subtitle: String {
        if let lastActive {
            let formatted = lastActive.formatted(.relative(presentation: .named))
            return "Full Access on · last used \(formatted)"
        }
        return "Full Access on — switch with 🌐 in any app"
    }
}

struct KeyboardSetupCard: View {
    @Binding var isExpanded: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    setupStep(number: 1, text: "Open Settings → General → Keyboard → Keyboards")
                    setupStep(number: 2, text: "Tap Add New Keyboard… → SayWell")
                    setupStep(number: 3, text: "Tap SayWell → turn on Allow Full Access")
                    setupStep(number: 4, text: "In any app, tap 🌐 to switch to SayWell")
                }

                Text("Full Access lets the keyboard reach the translation API. iOS will show Apple’s network prompt — that’s expected.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenSettings) {
                    Text("Open Settings")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(SayWellTheme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.75))
                Text("Enable SayWell in Settings")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(SayWellTheme.ink.opacity(0.55))
            }
        }
        .padding(16)
        .background(SayWellTheme.foam.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SayWellTheme.lagoon.opacity(0.12), lineWidth: 1)
        }
        .tint(SayWellTheme.brand)
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
