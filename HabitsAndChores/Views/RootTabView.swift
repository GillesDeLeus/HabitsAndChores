import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(SocialAccount.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }) private var tasks: [TaskItem]

    private let service: SocialService = CloudKitSocialService()

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
        .errorBanner()
        .task(id: account.userID) {
            if let me = account.userID {
                await SocialPushManager.registerSubscription(for: me)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active || phase == .background {
                Task { await ProfileSync.republish(account: account, tasks: tasks, service: service) }
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(SocialAccount())
}
