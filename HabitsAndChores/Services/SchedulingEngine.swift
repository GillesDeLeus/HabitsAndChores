import Foundation

/// A precomputed, by-day view of a task's completions for O(1) status lookups.
/// Streak and summary scans previously called `TaskItem.isCompleted(on:)` once per
/// occurrence date, each a linear scan of the whole completions array — O(occurrences
/// × completions). Building this set once turns each inner lookup into O(1).
struct CompletionIndex {
    private let doneDays: Set<Date>
    private let skippedDays: Set<Date>

    init(_ completions: [Completion], calendar: Calendar = .current) {
        var done: Set<Date> = []
        var skipped: Set<Date> = []
        for c in completions {
            let day = calendar.startOfDay(for: c.scheduledDate)
            switch c.status {
            case .done:    done.insert(day)
            case .skipped: skipped.insert(day)
            }
        }
        doneDays = done
        skippedDays = skipped
    }

    /// `day` must already be a start-of-day date (occurrence dates always are).
    func isDone(_ day: Date) -> Bool { doneDays.contains(day) }
    /// Skipped only counts when the day isn't also done (done wins, matching the
    /// previous `isCompleted`-first ordering).
    func isSkipped(_ day: Date) -> Bool { !doneDays.contains(day) && skippedDays.contains(day) }
}

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
        return occurrences(frequency: task.frequency, anchor: task.startDate,
                           in: interval, calendar: calendar)
    }

    /// Whether `task` is scheduled on the given `day`.
    /// For a floating rule this is its canonical occurrence day (the period start),
    /// so calendars/stats show one occurrence per period — use `occurrenceDate` for
    /// "is it outstanding *today*".
    static func isScheduled(_ task: TaskItem, on day: Date, calendar: Calendar = .current) -> Bool {
        guard !task.isArchived else { return false }
        return occurrenceDate(for: task, on: day, calendar: calendar) == calendar.startOfDay(for: day)
    }

    /// Whether a rule with the given anchor (start date) is scheduled on `day`.
    /// Used for shared household chores, which aren't `TaskItem`s.
    static func isScheduled(frequency: FrequencyRule, anchor: Date, on day: Date,
                            calendar: Calendar = .current) -> Bool {
        occurrenceDate(frequency: frequency, anchor: anchor, on: day, calendar: calendar)
            == calendar.startOfDay(for: day)
    }

    /// Occurrence dates for a bare rule+anchor within `interval` (inclusive).
    static func occurrences(frequency: FrequencyRule, anchor: Date, in interval: DateInterval,
                            calendar: Calendar = .current) -> [Date] {
        let anchorDay = calendar.startOfDay(for: anchor)
        let rangeStart = calendar.startOfDay(for: interval.start)
        let rangeEnd = calendar.startOfDay(for: interval.end)
        guard rangeStart <= rangeEnd else { return [] }

        if frequency.kind == .floating {
            return floatingOccurrences(unit: frequency.unit, anchor: anchorDay,
                                       rangeStart: rangeStart, rangeEnd: rangeEnd, calendar: calendar)
        }

        let start = max(anchorDay, rangeStart)
        guard start <= rangeEnd else { return [] }
        var result: [Date] = []
        var day = start
        while day <= rangeEnd {
            if matches(rule: frequency, day: day, anchor: anchorDay, calendar: calendar) {
                result.append(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    // MARK: - Occurrence date (completion key)

    /// The start-of-day date a completion is stored against for `task` on the given
    /// calendar `day`, or `nil` if the task isn't actionable that day.
    ///
    /// - Day-scheduled rules: `day` itself, when the task is scheduled then.
    /// - Floating rules: the **start of the period** (week/month) containing `day`,
    ///   for *every* day of that period until the task has started. This is what makes
    ///   a floating task stay outstanding all week/month yet record a single
    ///   completion per period (keyed at the period start).
    static func occurrenceDate(for task: TaskItem, on day: Date, calendar: Calendar = .current) -> Date? {
        guard !task.isArchived else { return nil }
        return occurrenceDate(frequency: task.frequency, anchor: task.startDate, on: day, calendar: calendar)
    }

    static func occurrenceDate(frequency rule: FrequencyRule, anchor: Date, on day: Date,
                               calendar: Calendar = .current) -> Date? {
        let normalized = calendar.startOfDay(for: day)
        let anchorDay = calendar.startOfDay(for: anchor)

        if rule.kind == .floating {
            guard let period = floatingPeriod(unit: rule.unit, containing: normalized, calendar: calendar)
            else { return nil }
            // Active only once the task has started: the period must reach the anchor.
            guard period.end > anchorDay else { return nil }
            return period.start
        }

        guard normalized >= anchorDay else { return nil }
        return matches(rule: rule, day: normalized, anchor: anchorDay, calendar: calendar) ? normalized : nil
    }

    /// Whether `task` should appear in a "today" list on `day`.
    ///
    /// - Day-scheduled rules: simply whether they're scheduled that day (a completed
    ///   one still shows, struck through, until the day rolls over).
    /// - Floating rules: outstanding for the current period, **or** completed *today*
    ///   so the just-finished row lingers (and stays undoable) until the day rolls
    ///   over — then it drops off until the next period, matching day-scheduled tasks.
    static func belongsInToday(_ task: TaskItem, on day: Date, calendar: Calendar = .current) -> Bool {
        guard let occ = occurrenceDate(for: task, on: day, calendar: calendar) else { return false }
        guard task.frequency.kind == .floating else { return true }
        if let done = (task.completions ?? []).first(where: {
            $0.status == .done && calendar.isDate($0.scheduledDate, inSameDayAs: occ)
        }) {
            return calendar.isDate(done.loggedAt, inSameDayAs: day)
        }
        return true
    }

    // MARK: - Floating periods

    /// The calendar period (week or month) containing `day` for a floating rule.
    static func floatingPeriod(unit: FrequencyRule.Unit, containing day: Date,
                               calendar: Calendar = .current) -> DateInterval? {
        let component: Calendar.Component = (unit == .month) ? .month : .weekOfYear
        return calendar.dateInterval(of: component, for: day)
    }

    /// Period-start dates for a floating rule whose start falls within
    /// `[rangeStart, rangeEnd]` (and whose period reaches the anchor). One date per
    /// period — the canonical occurrence used for streaks/stats/completion keying.
    private static func floatingOccurrences(unit: FrequencyRule.Unit, anchor: Date,
                                            rangeStart: Date, rangeEnd: Date,
                                            calendar: Calendar) -> [Date] {
        let component: Calendar.Component = (unit == .month) ? .month : .weekOfYear
        // Start from the period containing the later of the anchor and range start.
        guard var period = floatingPeriod(unit: unit, containing: max(anchor, rangeStart), calendar: calendar)
        else { return [] }
        var result: [Date] = []
        while period.start <= rangeEnd {
            if period.start >= rangeStart, period.end > anchor {
                result.append(period.start)
            }
            guard let nextDay = calendar.date(byAdding: component, value: 1, to: period.start),
                  let nextPeriod = floatingPeriod(unit: unit, containing: nextDay, calendar: calendar)
            else { break }
            period = nextPeriod
        }
        return result
    }

    // MARK: - Rule matching

    private static func matches(rule: FrequencyRule, day: Date, anchor: Date, calendar: Calendar) -> Bool {
        switch rule.kind {
        case .daily:
            return true

        case .floating:
            // Floating rules are resolved via `occurrenceDate`/`floatingOccurrences`,
            // never through per-day matching.
            return false

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
                // Count whole calendar months by month-index, independent of the
                // day-of-month — `dateComponents([.month])` is off-by-one when the
                // clamped day is earlier in the month than the anchor day.
                let anchorIndex = calendar.component(.year, from: anchor) * 12 + calendar.component(.month, from: anchor)
                let dayIndex = calendar.component(.year, from: day) * 12 + calendar.component(.month, from: day)
                let months = dayIndex - anchorIndex
                guard months >= 0, months % rule.interval == 0 else { return false }
                // Clamp the anchor day to this month's length, mirroring `.monthly`,
                // so a task anchored on the 31st still fires in short months.
                guard let range = calendar.range(of: .day, in: .month, for: day) else { return false }
                let lastDay = range.upperBound - 1
                let anchorDay = calendar.component(.day, from: anchor)
                return calendar.component(.day, from: day) == min(anchorDay, lastDay)
            }
        }
    }

    // MARK: - Streaks

    /// Current consecutive run of completed scheduled occurrences ending today
    /// (or the most recent past occurrence). Skips don't break a streak; misses do.
    static func currentStreak(for task: TaskItem, asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        currentStreak(for: task, index: CompletionIndex(task.completions ?? [], calendar: calendar),
                      asOf: today, calendar: calendar)
    }

    /// As `currentStreak`, but reusing a prebuilt `CompletionIndex` so callers that
    /// compute several derivations for the same task (e.g. the summary) build it once.
    static func currentStreak(for task: TaskItem, index: CompletionIndex,
                              asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        // Look back up to a year of scheduled occurrences.
        guard let yearAgo = calendar.date(byAdding: .year, value: -1, to: todayStart) else { return 0 }
        let occ = occurrences(for: task, in: DateInterval(start: yearAgo, end: todayStart), calendar: calendar)
            .sorted(by: >)

        var streak = 0
        for date in occ {
            if index.isDone(date) {
                streak += 1
            } else if index.isSkipped(date) {
                continue // skip doesn't break or extend
            } else if isCurrentPeriod(occurrence: date, frequency: task.frequency, today: todayStart, calendar: calendar) {
                continue // the in-progress occurrence/period (not yet done) is not a break
            } else {
                break
            }
        }
        return streak
    }

    /// Longest run of completed scheduled occurrences ever (within the last year).
    /// Like `currentStreak`, skips are neutral and a not-yet-done today doesn't break it.
    static func longestStreak(for task: TaskItem, asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        longestStreak(for: task, index: CompletionIndex(task.completions ?? [], calendar: calendar),
                      asOf: today, calendar: calendar)
    }

    static func longestStreak(for task: TaskItem, index: CompletionIndex,
                              asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        guard let yearAgo = calendar.date(byAdding: .year, value: -1, to: todayStart) else { return 0 }
        let occ = occurrences(for: task, in: DateInterval(start: yearAgo, end: todayStart), calendar: calendar)
            .sorted(by: <)

        var best = 0
        var run = 0
        for date in occ {
            if index.isDone(date) {
                run += 1
                best = max(best, run)
            } else if index.isSkipped(date) {
                continue // neutral
            } else if isCurrentPeriod(occurrence: date, frequency: task.frequency, today: todayStart, calendar: calendar) {
                continue // the in-progress occurrence/period doesn't break the run
            } else {
                run = 0
            }
        }
        return best
    }

    /// Whether `occurrence` is the current, not-yet-elapsed occurrence as of `today`
    /// — so a not-yet-done occurrence shouldn't break a streak. For day-scheduled
    /// rules that's literally today; for floating rules it's any day within the
    /// period that `occurrence` (a period start) opens.
    private static func isCurrentPeriod(occurrence: Date, frequency: FrequencyRule,
                                        today: Date, calendar: Calendar) -> Bool {
        guard frequency.kind == .floating else { return occurrence == today }
        guard let period = floatingPeriod(unit: frequency.unit, containing: occurrence, calendar: calendar)
        else { return occurrence == today }
        return period.start <= today && today < period.end
    }
}
