import Foundation
import SwiftData

enum CompletionStatus: String, Codable {
    case done
    case skipped
}

@Model
final class Completion {
    // Defaulted for CloudKit schema validity (see TaskItem). The initializer
    // overwrites these for real instances.
    var id: UUID = UUID()
    /// The scheduled day this entry refers to (normalized to start of day).
    var scheduledDate: Date = Date.now
    /// When the user actually marked it.
    var loggedAt: Date = Date.now
    var statusRaw: String = CompletionStatus.done.rawValue
    var task: TaskItem?

    init(
        id: UUID = UUID(),
        scheduledDate: Date,
        loggedAt: Date = .now,
        status: CompletionStatus,
        task: TaskItem? = nil
    ) {
        self.id = id
        self.scheduledDate = Calendar.current.startOfDay(for: scheduledDate)
        self.loggedAt = loggedAt
        self.statusRaw = status.rawValue
        self.task = task
    }

    var status: CompletionStatus {
        get { CompletionStatus(rawValue: statusRaw) ?? .done }
        set { statusRaw = newValue.rawValue }
    }
}
