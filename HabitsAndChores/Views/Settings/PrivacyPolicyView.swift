import SwiftUI

/// In-app rendering of the privacy policy (kept in sync with PRIVACY.md in the repo).
struct PrivacyPolicyView: View {
    private struct Item: Identifiable { let id = UUID(); let title: String; let body: String }

    private let updated = "14 June 2026"
    private let intro = "Habits & Chores is private by default. You can use the app fully without an account, and in that case your data never leaves your own devices and iCloud account."

    private let items: [Item] = [
        Item(title: "Data you create",
             body: "Tasks, habits, chores, to-dos and completions are stored locally on your device. If you are signed in to iCloud, they sync to your own private iCloud account via CloudKit. This data is not accessible to us — only to you, on your devices."),
        Item(title: "Optional account & social features",
             body: "These are opt-in. If you create an account, Sign in with Apple authenticates you and we receive a stable, app-specific identifier. A public profile is created containing your handle, display name, avatar and a summary of your progress (level, points, streaks, badge tiers) so friends can find and view you. Friend relationships are stored too. Your underlying habit history is never published — only the derived summary."),
        Item(title: "Photos",
             body: "If you pick a photo for your avatar, only that single image is used. It is resized to a small thumbnail and stored with your public profile. The app does not access your photo library beyond the image you select."),
        Item(title: "Notifications",
             body: "The app schedules local reminders on your device. If you use social features, it registers for CloudKit push notifications so you can be notified of friend requests. The push token is managed by Apple."),
        Item(title: "What we do NOT do",
             body: "No analytics, advertising or third-party tracking SDKs. We do not sell or share your data. We do not run our own servers — all syncing uses Apple iCloud/CloudKit."),
        Item(title: "Data retention & deletion",
             body: "Deleting the app removes on-device data. “Leave & delete profile” in Settings deletes your public profile and releases your handle. Your private iCloud data is controlled by you through your Apple iCloud settings."),
        Item(title: "Children",
             body: "The app is not directed to children under 13 and does not knowingly collect personal information from children."),
        Item(title: "Your rights",
             body: "Depending on your jurisdiction (e.g. GDPR in the EU/EEA), you may access, correct, export or delete your personal data. Most of this is available directly in-app; for anything else, contact us below."),
        Item(title: "Contact",
             body: "For privacy questions or requests: gilles.de.leus@outlook.com"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(intro)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        // Section headers are localized (chrome); the legal bodies
                        // stay verbatim English on purpose — see PRIVACY/TERMS.md.
                        Text(LocalizedStringKey(item.title)).font(.headline)
                        Text(verbatim: item.body).font(.callout).foregroundStyle(.secondary)
                    }
                }

                Text("Last updated: \(updated)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
