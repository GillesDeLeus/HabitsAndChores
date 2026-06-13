import Foundation

/// Describes how often a task recurs. Stored as a Codable value on `TaskItem`.
struct FrequencyRule: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case daily
        case weekly      // on specific weekdays
        case monthly     // on a specific day-of-month
        case everyN      // every N days/weeks/months from the start date
    }

    enum Unit: String, Codable, CaseIterable {
        case day, week, month
    }

    var kind: Kind
    /// Used by `.everyN`.
    var interval: Int
    /// Used by `.everyN`.
    var unit: Unit
    /// Used by `.weekly`. Calendar weekday numbers (1 = Sunday ... 7 = Saturday).
    var weekdays: [Int]
    /// Used by `.monthly`. 1...31; clamped to the last valid day of short months.
    var dayOfMonth: Int?

    // MARK: - Convenience constructors

    static var daily: FrequencyRule {
        FrequencyRule(kind: .daily, interval: 1, unit: .day, weekdays: [], dayOfMonth: nil)
    }

    static func weekly(on weekdays: [Int]) -> FrequencyRule {
        FrequencyRule(kind: .weekly, interval: 1, unit: .week, weekdays: weekdays.sorted(), dayOfMonth: nil)
    }

    static func monthly(day: Int) -> FrequencyRule {
        FrequencyRule(kind: .monthly, interval: 1, unit: .month, weekdays: [], dayOfMonth: day)
    }

    static func every(_ interval: Int, _ unit: Unit) -> FrequencyRule {
        FrequencyRule(kind: .everyN, interval: max(1, interval), unit: unit, weekdays: [], dayOfMonth: nil)
    }

    // MARK: - Display

    /// A short, localizable, human-readable summary.
    var localizedDescription: String {
        switch kind {
        case .daily:
            return String(localized: "Every day")
        case .weekly:
            if weekdays.isEmpty { return String(localized: "Weekly") }
            let names = weekdays.map { Self.shortWeekdaySymbol($0) }.joined(separator: ", ")
            return String(localized: "Weekly on \(names)")
        case .monthly:
            let d = dayOfMonth ?? 1
            return String(localized: "Monthly on day \(d)")
        case .everyN:
            switch unit {
            case .day:   return String(localized: "Every \(interval) days")
            case .week:  return String(localized: "Every \(interval) weeks")
            case .month: return String(localized: "Every \(interval) months")
            }
        }
    }

    private static func shortWeekdaySymbol(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols // index 0 == Sunday
        let idx = (weekday - 1) % 7
        return symbols.indices.contains(idx) ? symbols[idx] : "?"
    }
}
