import SwiftUI

struct RecentTranslationsSection: View {
    let entries: [TranslationHistoryEntry]
    let onSelect: (TranslationHistoryEntry) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.75))
                Spacer()
                Button("Clear", action: onClear)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(SayWellTheme.lagoon.opacity(0.8))
            }

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        RecentTranslationRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct RecentTranslationRow: View {
    let entry: TranslationHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.singlish)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(SayWellTheme.ink)
                .lineLimit(1)

            Text(entry.english)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(SayWellTheme.lagoon.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(SayWellTheme.foam.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SayWellTheme.lagoon.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.singlish), translated as \(entry.english)")
    }
}
