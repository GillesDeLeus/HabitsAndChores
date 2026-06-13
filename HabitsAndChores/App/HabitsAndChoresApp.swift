import SwiftUI
import SwiftData
import OSLog

@main
struct HabitsAndChoresApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer
    @State private var social = SocialAccount()

    init() {
        let schema = Schema([TaskItem.self, Completion.self, TodoItem.self])
        // CloudKit-backed automatic iCloud sync. Falls back to local-only if
        // the iCloud capability is not configured for the run destination.
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fall back to a local-only store so the app still launches in
            // environments without iCloud (e.g. previews, CI, unsigned builds).
            Logger.cloudkit.error("CloudKit container init failed, falling back to local-only store: \(error.localizedDescription, privacy: .public)")
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            container = (try? ModelContainer(for: schema, configurations: [local]))
                ?? (try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(social)
                .task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        }
        .modelContainer(container)
    }
}
