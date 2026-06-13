import SwiftUI

struct RootTabView: View {
    @Environment(SocialAccount.self) private var account

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            TasksHostView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }

            AwardsView()
                .tabItem { Label("Awards", systemImage: "trophy.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .task(id: account.userID) {
            if let me = account.userID {
                await SocialPushManager.registerSubscription(for: me)
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(SocialAccount())
}
