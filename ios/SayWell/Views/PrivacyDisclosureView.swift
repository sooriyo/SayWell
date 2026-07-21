import SwiftUI

struct PrivacyDisclosureView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("hasSeenPrivacyDisclosure") var hasSeenPrivacyDisclosure = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Privacy Matters")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Here's what SayWell collects and how we use it")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)

                    Divider()

                    // What we collect
                    VStack(alignment: .leading, spacing: 12) {
                        Label("What We Collect", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundColor(.blue)

                        PrivacyItem(
                            title: "Text You Type",
                            description: "The Singlish text you enter for translation",
                            detail: "Used only for translation & caching (30 days)"
                        )

                        PrivacyItem(
                            title: "Device ID",
                            description: "A random identifier generated on first app launch",
                            detail: "Used only to enforce fair rate limits (60 requests/minute)"
                        )
                    }

                    Divider()

                    // What we don't collect
                    VStack(alignment: .leading, spacing: 12) {
                        Label("What We Don't Collect", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("✕ No personal information (name, email, phone)")
                            BulletPoint("✕ No user tracking across apps or websites")
                            BulletPoint("✕ No ads, analytics, or behavioral profiling")
                            BulletPoint("✕ No selling or sharing your data")
                        }
                    }

                    Divider()

                    // Third parties
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Third Parties", systemImage: "network")
                            .font(.headline)
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your text is sent to Google Gemini API for translation.")
                                .font(.callout)
                            Link("View Google's Privacy Policy", destination: URL(string: "https://policies.google.com/privacy")!)
                                .font(.callout)
                                .foregroundColor(.blue)
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }

                    Divider()

                    // Your controls
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your Controls", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundColor(.purple)

                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("Delete cached phrases anytime in Settings")
                            BulletPoint("Disable the keyboard without data loss")
                            BulletPoint("Request data deletion anytime")
                        }
                    }

                    Divider()

                    // Read full policy
                    VStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/sooriyo/SayWell/blob/master/PRIVACY_POLICY.md")!) {
                            HStack {
                                Text("Read Full Privacy Policy")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.up.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }

                        Link(destination: URL(string: "https://github.com/sooriyo/SayWell/blob/master/TERMS_OF_SERVICE.md")!) {
                            HStack {
                                Text("Read Terms of Service")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.up.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color(.systemGray3))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Privacy Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Got It") {
                        hasSeenPrivacyDisclosure = true
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct PrivacyItem: View {
    let title: String
    let description: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(8)
                .background(Color(.systemBlue).opacity(0.1))
                .cornerRadius(4)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .fontWeight(.bold)
            Text(text)
                .font(.callout)
        }
    }
}

#Preview {
    PrivacyDisclosureView()
}
