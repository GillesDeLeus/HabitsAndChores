import Foundation
import SwiftData
import SwiftUI

enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case habit
    case chore
    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .habit: return String(localized: "Habit")
        case .chore: return String(localized: "Chore")
        }
    }
}

enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case home, health, finance, pets, productivity, social, other
    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .home:         return String(localized: "Home")
        case .health:       return String(localized: "Health")
        case .finance:      return String(localized: "Finance")
        case .pets:         return String(localized: "Pets")
        case .productivity: return String(localized: "Productivity")
        case .social:       return String(localized: "Social")
        case .other:        return String(localized: "Other")
        }
    }

    var symbolName: String {
        switch self {
        case .home:         return "house.fill"
        case .health:       return "heart.fill"
        case .finance:      return "dollarsign.circle.fill"
        case .pets:         return "pawprint.fill"
        case .productivity: return "checklist"
        case .social:       return "person.2.fill"
        case .other:        return "star.fill"
        }
    }
}

@Model
final class TaskItem {
    // All stored attributes have default values so the schema is valid for
    // CloudKit mirroring (which requires every attribute to be optional or
    // defaulted). The initializer overwrites these for real instances.
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var kindRaw: String = TaskKind.chore.rawValue
    var categoryRaw: String = TaskCategory.other.rawValue
    var frequency: FrequencyRule = FrequencyRule.daily
    var symbolName: String = "checklist"
    /// Stored hue 0...1 used to derive the accent color.
    var colorHue: Double = 0.58
    /// First date the task is active / scheduling anchor.
    var startDate: Date = Date.now
    /// Optional preferred reminder time (hour/minute encoded via DateComponents on the day).
    var reminderHour: Int?
    var reminderMinute: Int?
    var isArchived: Bool = false
    var createdFromTemplateID: String?
    var createdAt: Date = Date.now
    /// User-controlled manual ordering (lower = higher in the list).
    var sortIndex: Int = 0

    // CloudKit requires relationships to be optional.
    @Relationship(deleteRule: .cascade, inverse: \Completion.task)
    var completions: [Completion]? = nil

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        kind: TaskKind,
        category: TaskCategory,
        frequency: FrequencyRule,
        symbolName: String? = nil,
        colorHue: Double = 0.58,
        startDate: Date = Calendar.current.startOfDay(for: .now),
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil,
        isArchived: Bool = false,
        createdFromTemplateID: String? = nil,
        sortIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.kindRaw = kind.rawValue
        self.categoryRaw = category.rawValue
        self.frequency = frequency
        self.symbolName = symbolName ?? category.symbolName
        self.colorHue = colorHue
        self.startDate = startDate
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.isArchived = isArchived
        self.createdFromTemplateID = createdFromTemplateID
        self.createdAt = .now
        // Default to a monotonically increasing value so new tasks append in order.
        self.sortIndex = sortIndex ?? Int(Date.now.timeIntervalSince1970)
    }

    // MARK: - Derived

    var kind: TaskKind { TaskKind(rawValue: kindRaw) ?? .chore }
    var category: TaskCategory { TaskCategory(rawValue: categoryRaw) ?? .other }
    var color: Color { Color(hue: colorHue, saturation: 0.65, brightness: 0.9) }

    var hasReminder: Bool { reminderHour != nil && reminderMinute != nil }

    /// Whether the task has a completion logged as done for the given day.
    func isCompleted(on day: Date, calendar: Calendar = .current) -> Bool {
        (completions ?? []).contains { $0.status == .done && calendar.isDate($0.scheduledDate, inSameDayAs: day) }
    }

    func completion(on day: Date, calendar: Calendar = .current) -> Completion? {
        (completions ?? []).first { calendar.isDate($0.scheduledDate, inSameDayAs: day) }
    }
}
