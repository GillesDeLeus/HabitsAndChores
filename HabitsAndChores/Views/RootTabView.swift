import SwiftUI
import SwiftData
import WidgetKit
import AuthenticationServices
import OSLog

struct RootTabView: View {
    @Environment(SocialAccount.self) private var account
    @Environment(HouseholdsModel.self) private var households
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }) private var tasks: [TaskItem]

    @AppStorage("hasCompletedOnboarding") private var onboardingComplete = false
    @State private var showOnboarding = false

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
        .onAppear { if !onboardingComplete { showOnboarding = true } }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                onboardingComplete = true
                showOnboarding = false
                Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
            }
        }
        .task {
            // Returning users (onboarding already done): ask for notifications here
            // rather than over the first-run onboarding.
            if onboardingComplete { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        }
        .task(id: account.userID) {
            if let me = account.userID {
                await SocialPushManager.registerSubscription(for: me)
                await verifyAppleCredential(me)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            if let me = account.userID { Task { await verifyAppleCredential(me) } }
        }
        .task(id: account.cloudUserRecordName) {
            // Load the shared households once for the whole app so every tab
            // (Today / Tasks / To-Do / Settings) sees the same data.
            households.meRecordName = account.cloudUserRecordName
            households.meDisplayName = account.displayName
            households.meUserID = account.userID
            await households.registerSubscriptions()
            await households.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .householdsChanged)) { _ in
            Task { await households.reload() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let me = account.userID { Task { await verifyAppleCredential(me) } }
            if phase == .active { Task { await households.drainOutbox() } }   // flush offline household writes
            if phase == .active || phase == .background {
                Task { await ProfileSync.republish(account: account, tasks: tasks, service: service) }
            }
            // Refresh the widget when leaving the app, so it reflects the latest data.
            if phase == .background { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    /// If the user's Sign in with Apple credential was revoked (or no longer exists),
    /// sign them out locally — Apple-recommended. No-op if the check can't complete.
    private func verifyAppleCredential(_ userID: String) async {
        let state = await withCheckedContinuation { (cont: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                cont.resume(returning: state)
            }
        }
        if state == .revoked || state == .notFound {
            Logger.social.info("Apple credential \(state == .revoked ? "revoked" : "not found", privacy: .public); signing out locally")
            account.markLeft()
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(SocialAccount())
        .environment(HouseholdsModel())
}
