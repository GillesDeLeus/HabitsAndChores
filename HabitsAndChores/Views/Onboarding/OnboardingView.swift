import SwiftUI

/// First-run guided intro: what the app is, habits vs. chores, templates, and the
/// optional (private-by-default) account. Shown once.
struct OnboardingView: View {
    let onDone: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let systemImage: String
        let tint: Color
        let title: String
        let message: String
        var bullets: [(symbol: String, text: String)] = []
    }

    private let pages: [Page] = [
        Page(systemImage: "checklist",
             tint: .accentColor,
             title: "Habits & Chores",
             message: "Track the things you want to do and the things you need to do — with flexible schedules, reminders, streaks, and a home-screen widget."),
        Page(systemImage: "arrow.triangle.2.circlepath",
             tint: .green,
             title: "Two kinds of tasks",
             message: "Both repeat on a schedule you choose, and you check them off each day on the Today tab.",
             bullets: [
                ("heart.fill", "Habits — routines you want to build, like drinking water or reading."),
                ("house.fill", "Chores — upkeep you need to stay on top of, like taking out the bins."),
             ]),
        Page(systemImage: "books.vertical.fill",
             tint: .orange,
             title: "Start in seconds",
             message: "Add ready-made habits and chores from the built-in template library, then make them your own. You can also add one-off items in the To-Do list."),
        Page(systemImage: "person.2.fill",
             tint: .purple,
             title: "Private by default",
             message: "Your data stays on your device and in your iCloud. Optionally create an account to add friends, share a household, and split chores together."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { onDone() }
                    .padding()
            }

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == pages.count - 1 ? "Get Started" : "Continue") {
                if page == pages.count - 1 {
                    onDone()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func pageView(_ page: Page) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 72))
                    .foregroundStyle(page.tint)
                    .padding(.top, 48)
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !page.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(page.bullets, id: \.text) { bullet in
                            Label {
                                Text(bullet.text)
                            } icon: {
                                Image(systemName: bullet.symbol).foregroundStyle(page.tint)
                            }
                            .font(.callout)
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    OnboardingView {}
}
