import SwiftUI

/// In-app rendering of the Terms of Use & Community Guidelines (kept in sync with
/// TERMS.md). Required because the app hosts user-generated content.
struct TermsView: View {
    private struct Item: Identifiable { let id = UUID(); let title: String; let body: String }

    private let updated = "13 June 2026"
    private let intro = "These terms apply when you create an account and use the social features. Using the app without an account does not require agreement to the social terms below."

    private let items: [Item] = [
        Item(title: "Acceptable use",
             body: "There is zero tolerance for objectionable content or abusive behavior. By creating an account you agree not to use an offensive handle, name, avatar or content; not to harass, abuse, threaten or impersonate others; and not to use the service for spam or unlawful activity."),
        Item(title: "Moderation, reporting & blocking",
             body: "User-entered handles and names are filtered for objectionable terms. You can report any user from their profile, and you can block any user to remove and hide them. We aim to act on reports within 24 hours, which may include removing content and ejecting the user who provided it."),
        Item(title: "Accounts",
             body: "Accounts are authenticated with Sign in with Apple. You may delete your account anytime in Settings → Account → Leave & delete profile, which removes your public profile and connections."),
        Item(title: "Disclaimer",
             body: "The app is provided “as is” without warranties. The source code is available under the MIT license."),
        Item(title: "Contact",
             body: "For questions, reports or requests: gilles.de.leus@outlook.com"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(intro).font(.callout).foregroundStyle(.secondary)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text(item.body).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Last updated: \(updated)").font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { TermsView() }
}
