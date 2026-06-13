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

/// A one-off to-do, independent of the recurring habits/chores system. Supports a
/// due date, an optional reminder, a priority, and manual ordering.
@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date.now
    var completedAt: Date?
    var dueDate: Date?
    var reminderDate: Date?
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

    var hasReminder: Bool { reminderDate != nil }

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < .now
    }

    func toggle() {
        isDone.toggle()
        completedAt = isDone ? .now : nil
    }
}
