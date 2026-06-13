import Foundation
import OSLog
import SwiftData

/// Centralized loggers, replacing scattered `print()` calls (item: observability).
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "HabitsAndChores"
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let social = Logger(subsystem: subsystem, category: "social")
    static let cloudkit = Logger(subsystem: subsystem, category: "cloudkit")
}

/// Holds the most recent user-facing error so the app can show a transient banner
/// instead of silently swallowing failures.
@MainActor
@Observable
final class AppErrorCenter {
    static let shared = AppErrorCenter()
    private init() {}
    var message: String?
    func report(_ message: String) { self.message = message }
}

extension ModelContext {
    /// Saves and, on failure, logs and surfaces a user-facing message — replacing
    /// the scattered `try? save()` calls that previously swallowed errors.
    func saveOrReport(_ operation: String = #function) {
        do {
            try save()
        } catch {
            Logger.persistence.error("Save failed during \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in
                AppErrorCenter.shared.report(String(localized: "Couldn’t save your changes. Please try again."))
            }
        }
    }
}
