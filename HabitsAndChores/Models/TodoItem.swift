import Foundation
import SwiftData
import SwiftUI

enum TodoPriority: Int, CaseIterable, Identifiable, Codable {
    case none = 0, low, medium, high
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none:   return String(localized: "None")
        case .low:    return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high:   return String(localized: "High")
        }
    }

    /// Flag tint; `.none` has no visible flag.
    var color: Color {
        switch self {
        case .none:   return .clear
        case .low:    return .blue
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

enum TodoReminderMode: Int, CaseIterable, Identifiable, Codable {
    case none = 0, atTime, beforeDue, dailyUntilDone
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none:            return String(localized: "None")
        case .atTime:          return String(localized: "At a time")
        case .beforeDue:       return String(localized: "Before it's due")
        case .dailyUntilDone:  return String(localized: "Every day until done")
        }
    }
}

/// Preset offsets for a "before it's due" reminder.
enum TodoReminderOffset {
    static let options: [(seconds: Double, label: String)] = [
        (0,      String(localized: "At the due time")),
        (600,    String(localized: "10 minutes before")),
        (3600,   String(localized: "1 hour before")),
        (86_400, String(localized: "1 day before")),
        (604_800, String(localized: "1 week before")),
    ]
    static func label(for seconds: Double) -> String {
        options.first { $0.seconds == seconds }?.label ?? String(localized: "Before it's due")
    }
}

/// A one-off to-do, independent of the recurring habits/chores system. Supports a
/// due date, a flexible reminder (at a time / relative to due / recurring), a
/// priority, an optional category, and manual ordering.
@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date.now
    var completedAt: Date?
    var dueDate: Date?
    var reminderModeRaw: Int = 0
    var reminderDate: Date?         // .atTime fire date, or .dailyUntilDone time-of-day
    var reminderOffset: Double = 0  // .beforeDue: seconds before the due date
    var priorityRaw: Int = 0
    var categoryRaw: String = ""    // empty = no category
    /// User-controlled manual ordering (lower = higher in the list).
    var sortIndex: Int = 0

    init(title: String, sortIndex: Int? = nil) {
        self.id = UUID()
        self.title = title
        self.isDone = false
        self.createdAt = .now
        self.completedAt = nil
        self.sortIndex = sortIndex ?? Int(Date.now.timeIntervalSince1970)
    }

    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var category: TaskCategory? {
        get { categoryRaw.isEmpty ? nil : TaskCategory(rawValue: categoryRaw) }
        set { categoryRaw = newValue?.rawValue ?? "" }
    }

    var reminderMode: TodoReminderMode {
        get { TodoReminderMode(rawValue: reminderModeRaw) ?? .none }
        set { reminderModeRaw = newValue.rawValue }
    }

    var hasReminder: Bool { reminderMode != .none }

    /// Short human-readable summary of the reminder, for list rows.
    var reminderSummary: String? {
        switch reminderMode {
        case .none:
            return nil
        case .atTime:
            return reminderDate?.formatted(date: .abbreviated, time: .shortened)
        case .beforeDue:
            return TodoReminderOffset.label(for: reminderOffset)
        case .dailyUntilDone:
            let time = reminderDate?.formatted(date: .omitted, time: .shortened) ?? ""
            return String(localized: "Daily \(time)")
        }
    }

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < .now
    }

    func toggle() {
        isDone.toggle()
        completedAt = isDone ? .now : nil
    }
}
