import SwiftUI
import SwiftData
import OSLog

@main
struct HabitsAndChoresApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer
    @State private var social = SocialAccount()
    @State private var households = HouseholdsModel()
    @State private var language = LanguageManager()

    init() {
        CrashReporter.install()
        CrashReporter.reportPreviousCrashIfNeeded()

        let schema = Schema([TaskItem.self, Completion.self, TodoItem.self])
        // CloudKit-backed automatic iCloud sync. Falls back to local-only if
        // the iCloud capability is not configured for the run destination.
        // Store in the shared App Group container so the widget reads the same data.
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(AppGroup.id),
            cloudKitDatabase: .automatic
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fall back to a local-only store so the app still launches in
            // environments without iCloud (e.g. previews, CI, unsigned builds).
            Logger.cloudkit.error("CloudKit container init failed, falling back to local-only store: \(error.localizedDescription, privacy: .public)")
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                           groupContainer: .identifier(AppGroup.id), cloudKitDatabase: .none)
            container = (try? ModelContainer(for: schema, configurations: [local]))
                ?? (try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(social)
                .environment(households)
                .environment(language)
                .environment(\.locale, language.locale)
                .id(language.code)   // rebuild the tree so live language changes re-resolve strings
        }
        .modelContainer(container)
    }
}
