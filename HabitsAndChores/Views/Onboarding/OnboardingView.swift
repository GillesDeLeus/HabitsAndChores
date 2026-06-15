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
        Page(systemImage: "repeat",
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
             message: "Add ready-made habits and chores from the built-in template library, then make them your own.",
             bullets: [
                ("checklist", "Keep one-off tasks in the To-Do list."),
                ("line.3.horizontal.decrease.circle", "Search, sort and filter your lists to find anything fast."),
             ]),
        Page(systemImage: "person.2.fill",
             tint: .purple,
             title: "Share & split chores",
             message: "Create a household, then give any task a household and a person — it shows up in their lists too.",
             bullets: [
                ("person.crop.circle.badge.checkmark", "Assign a chore to one person, or leave it for anyone."),
                ("arrow.triangle.2.circlepath", "Turn on rotation and a chore passes to the next member after each time it's done."),
                ("person.2.badge.plus", "Invite friends right in the app — they get a notification and accept it there."),
             ]),
        Page(systemImage: "lock.fill",
             tint: .blue,
             title: "Private by default",
             message: "Use the whole app without an account — your data stays on your device and in your own iCloud. An optional account adds friends and shared households; only tasks you put in a household are shared."),
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
