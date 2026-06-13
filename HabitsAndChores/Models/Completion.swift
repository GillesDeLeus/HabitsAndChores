import Foundation
import SwiftData

enum CompletionStatus: String, Codable {
    case done
    case skipped
}

@Model
final class Completion {
    var id: UUID
    /// The scheduled day this entry refers to (normalized to start of day).
    var scheduledDate: Date
    /// When the user actually marked it.
    var loggedAt: Date
    var statusRaw: String
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
