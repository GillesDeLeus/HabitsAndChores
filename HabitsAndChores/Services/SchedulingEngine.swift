import Foundation

/// Generates concrete occurrence dates from a `TaskItem`'s `FrequencyRule`.
/// Occurrences are never persisted — they are computed on demand for whatever
/// date range a view needs (today, a calendar month, etc.).
enum SchedulingEngine {

    /// Returns the start-of-day dates on which `task` is scheduled within
    /// `interval` (inclusive of both bounds).
    static func occurrences(
        for task: TaskItem,
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [Date] {
        guard !task.isArchived else { return [] }

        let start = calendar.startOfDay(for: max(task.startDate, interval.start))
        let end = calendar.startOfDay(for: interval.end)
        guard start <= end else { return [] }

        let rule = task.frequency
        let anchor = calendar.startOfDay(for: task.startDate)
        var result: [Date] = []

        var day = start
        while day <= end {
            if matches(rule: rule, day: day, anchor: anchor, calendar: calendar) {
                result.append(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Whether `task` is scheduled on the given `day`.
    static func isScheduled(_ task: TaskItem, on day: Date, calendar: Calendar = .current) -> Bool {
        guard !task.isArchived else { return false }
        let normalized = calendar.startOfDay(for: day)
        guard normalized >= calendar.startOfDay(for: task.startDate) else { return false }
        return matches(rule: task.frequency, day: normalized,
                       anchor: calendar.startOfDay(for: task.startDate), calendar: calendar)
    }

    // MARK: - Rule matching

    private static func matches(rule: FrequencyRule, day: Date, anchor: Date, calendar: Calendar) -> Bool {
        switch rule.kind {
        case .daily:
            return true

        case .weekly:
            let weekday = calendar.component(.weekday, from: day)
            return rule.weekdays.contains(weekday)

        case .monthly:
            let target = rule.dayOfMonth ?? 1
            let dayOfMonth = calendar.component(.day, from: day)
            guard let range = calendar.range(of: .day, in: .month, for: day) else { return false }
            let lastDay = range.upperBound - 1
            // If target exceeds the month length, fire on the last day of the month.
            return dayOfMonth == min(target, lastDay)

        case .everyN:
            switch rule.unit {
            case .day:
                let days = calendar.dateComponents([.day], from: anchor, to: day).day ?? 0
                return days >= 0 && days % rule.interval == 0
            case .week:
                guard calendar.component(.weekday, from: day) == calendar.component(.weekday, from: anchor)
                else { return false }
                let weeks = calendar.dateComponents([.weekOfYear], from: anchor, to: day).weekOfYear ?? -1
                return weeks >= 0 && weeks % rule.interval == 0
            case .month:
                guard calendar.component(.day, from: day) == calendar.component(.day, from: anchor)
                else { return false }
                let months = calendar.dateComponents([.month], from: anchor, to: day).month ?? -1
                return months >= 0 && months % rule.interval == 0
            }
        }
    }

    // MARK: - Streaks

    /// Current consecutive run of completed scheduled occurrences ending today
    /// (or the most recent past occurrence). Skips don't break a streak; misses do.
    static func currentStreak(for task: TaskItem, asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        // Look back up to a year of scheduled occurrences.
        guard let yearAgo = calendar.date(byAdding: .year, value: -1, to: todayStart) else { return 0 }
        let occ = occurrences(for: task, in: DateInterval(start: yearAgo, end: todayStart), calendar: calendar)
            .sorted(by: >)

        var streak = 0
        for date in occ {
            if task.isCompleted(on: date, calendar: calendar) {
                streak += 1
            } else if let c = task.completion(on: date, calendar: calendar), c.status == .skipped {
                continue // skip doesn't break or extend
            } else if date == todayStart {
                continue // today not yet done is not a break
            } else {
                break
            }
        }
        return streak
    }

    /// Longest run of completed scheduled occurrences ever (within the last year).
    /// Like `currentStreak`, skips are neutral and a not-yet-done today doesn't break it.
    static func longestStreak(for task: TaskItem, asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        guard let yearAgo = calendar.date(byAdding: .year, value: -1, to: todayStart) else { return 0 }
        let occ = occurrences(for: task, in: DateInterval(start: yearAgo, end: todayStart), calendar: calendar)
            .sorted(by: <)

        var best = 0
        var run = 0
        for date in occ {
            if task.isCompleted(on: date, calendar: calendar) {
                run += 1
                best = max(best, run)
            } else if let c = task.completion(on: date, calendar: calendar), c.status == .skipped {
                continue // neutral
            } else if date == todayStart {
                continue // today not yet done doesn't break the run
            } else {
                run = 0
            }
        }
        return best
    }
}
