import XCTest
@testable import HabitsAndChores

final class SchedulingEngineTests: XCTestCase {

    /// Fixed UTC Gregorian calendar so date math is deterministic across machines.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func task(_ frequency: FrequencyRule, start: Date, archived: Bool = false) -> TaskItem {
        TaskItem(title: "t", kind: .habit, category: .other, frequency: frequency,
                 startDate: start, isArchived: archived)
    }

    func testDailyOccurrencesAreInclusive() {
        let t = task(.daily, start: date(2026, 1, 1))
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: date(2026, 1, 1), end: date(2026, 1, 7)), calendar: cal)
        XCTAssertEqual(occ.count, 7)
    }

    func testWeeklyOnlyMatchesSelectedWeekdays() {
        // Weekdays 2 (Mon) and 4 (Wed).
        let t = task(.weekly(on: [2, 4]), start: date(2026, 1, 1))
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: date(2026, 1, 1), end: date(2026, 1, 14)), calendar: cal)
        XCTAssertEqual(occ.count, 4, "Two matching weekdays over two weeks")
        for d in occ {
            XCTAssertTrue([2, 4].contains(cal.component(.weekday, from: d)))
        }
    }

    func testEveryNDaysFromAnchor() {
        let start = date(2026, 1, 1)
        let t = task(.every(3, .day), start: start)
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: start, end: date(2026, 1, 10)), calendar: cal)
        // Days 0, 3, 6, 9 from the anchor.
        XCTAssertEqual(occ.count, 4)
        XCTAssertEqual(occ.first, start)
    }

    func testMonthlyFiresOncePerMonth() {
        let t = task(.monthly(day: 15), start: date(2026, 1, 1))
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: date(2026, 1, 1), end: date(2026, 3, 31)), calendar: cal)
        XCTAssertEqual(occ.count, 3)
        XCTAssertTrue(occ.allSatisfy { cal.component(.day, from: $0) == 15 })
    }

    func testMonthlyClampsToShortMonth() {
        // Day 31 in February (2026 is not a leap year) clamps to the 28th.
        let t = task(.monthly(day: 31), start: date(2026, 2, 1))
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: date(2026, 2, 1), end: date(2026, 2, 28)), calendar: cal)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(cal.component(.day, from: occ[0]), 28)
    }

    func testEveryNMonthsClampsToShortMonth() {
        // Anchored on the 31st, every 1 month: February (28 days, 2026) should fire
        // on the 28th rather than skipping the month entirely.
        let t = task(.every(1, .month), start: date(2026, 1, 31))
        XCTAssertTrue(SchedulingEngine.isScheduled(t, on: date(2026, 2, 28), calendar: cal),
                      "every-month-on-31st should fire on the last day of a short month")
        XCTAssertFalse(SchedulingEngine.isScheduled(t, on: date(2026, 2, 27), calendar: cal))
        XCTAssertTrue(SchedulingEngine.isScheduled(t, on: date(2026, 3, 31), calendar: cal))
    }

    func testEveryNMonthsRespectsIntervalAcrossShortMonths() {
        // Every 2 months from Jan 31: fires Jan 31, Mar 31, May 31 — *not* in the
        // intervening months, even though Feb's clamped day (28) is in range.
        let t = task(.every(2, .month), start: date(2026, 1, 31))
        XCTAssertTrue(SchedulingEngine.isScheduled(t, on: date(2026, 1, 31), calendar: cal))
        XCTAssertFalse(SchedulingEngine.isScheduled(t, on: date(2026, 2, 28), calendar: cal),
                       "an off-interval month must not fire just because the day clamps into range")
        XCTAssertTrue(SchedulingEngine.isScheduled(t, on: date(2026, 3, 31), calendar: cal))
        XCTAssertFalse(SchedulingEngine.isScheduled(t, on: date(2026, 4, 30), calendar: cal))
        XCTAssertTrue(SchedulingEngine.isScheduled(t, on: date(2026, 5, 31), calendar: cal))
    }

    // MARK: - Floating ("once a week / once a month")

    func testFloatingWeeklyHasOneOccurrencePerWeek() {
        // Jan 4 2026 is a Sunday (UTC Gregorian week starts Sunday). Three full weeks.
        let t = task(.floating(.week), start: date(2026, 1, 4))
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: date(2026, 1, 4), end: date(2026, 1, 24)), calendar: cal)
        XCTAssertEqual(occ.count, 3, "one occurrence per week")
        // Each occurrence is the start of its week (Sunday).
        XCTAssertTrue(occ.allSatisfy { cal.component(.weekday, from: $0) == cal.firstWeekday })
    }

    func testFloatingOccurrenceDateIsConstantAcrossTheWeek() {
        let t = task(.floating(.week), start: date(2026, 1, 4))
        let weekStart = SchedulingEngine.occurrenceDate(for: t, on: date(2026, 1, 4), calendar: cal)
        XCTAssertEqual(weekStart, date(2026, 1, 4))
        // Every day of that week resolves to the same completion key.
        for d in 4...10 {
            XCTAssertEqual(SchedulingEngine.occurrenceDate(for: t, on: date(2026, 1, d), calendar: cal),
                           weekStart, "day \(d) should key to the week start")
        }
        // The next week resolves to a different key.
        XCTAssertEqual(SchedulingEngine.occurrenceDate(for: t, on: date(2026, 1, 11), calendar: cal),
                       date(2026, 1, 11))
    }

    func testFloatingIsScheduledOnlyOnPeriodStart() {
        // `isScheduled` (used by the calendar/stats) marks the canonical period-start
        // day only, even though the task is *outstanding* every day via occurrenceDate.
        let t = task(.floating(.week), start: date(2026, 1, 4))
        XCTAssertTrue(SchedulingEngine.isScheduled(t, on: date(2026, 1, 4), calendar: cal))
        XCTAssertFalse(SchedulingEngine.isScheduled(t, on: date(2026, 1, 7), calendar: cal))
        XCTAssertNotNil(SchedulingEngine.occurrenceDate(for: t, on: date(2026, 1, 7), calendar: cal),
                        "still outstanding mid-week")
    }

    func testFloatingNotActiveBeforeStartDate() {
        // Started mid-week (Wed Jan 7). The week containing the anchor is active; the
        // prior week is not.
        let t = task(.floating(.week), start: date(2026, 1, 7))
        XCTAssertEqual(SchedulingEngine.occurrenceDate(for: t, on: date(2026, 1, 8), calendar: cal),
                       date(2026, 1, 4), "the anchor's own week is active from its start day")
        XCTAssertNil(SchedulingEngine.occurrenceDate(for: t, on: date(2025, 12, 30), calendar: cal),
                     "a week that ended before the task started is not active")
    }

    func testFloatingMonthlyHasOneOccurrencePerMonth() {
        let t = task(.floating(.month), start: date(2026, 1, 1))
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: date(2026, 1, 1), end: date(2026, 3, 31)), calendar: cal)
        XCTAssertEqual(occ.count, 3)
        XCTAssertTrue(occ.allSatisfy { cal.component(.day, from: $0) == 1 })
    }

    // These two use `Calendar.current` so the completion dates line up with
    // `Completion.init`, which normalizes via `Calendar.current` (a UTC test
    // calendar would shift the day keys by the local offset).

    func testFloatingWeeklyStreakCountsCompletedWeeksAndIgnoresInProgressWeek() {
        let c = Calendar.current
        let today = c.startOfDay(for: .now)
        let thisWeek = c.dateInterval(of: .weekOfYear, for: today)!.start
        func weekStart(_ weeksAgo: Int) -> Date { c.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)! }

        let t = TaskItem(title: "t", kind: .habit, category: .other,
                         frequency: .floating(.week), startDate: weekStart(6))
        // Done weeks 1, 2, 3 — the current week (0) is left undone.
        for w in [1, 2, 3] {
            t.completions = (t.completions ?? []) + [Completion(scheduledDate: weekStart(w), status: .done, task: t)]
        }
        // The in-progress current week (not yet done) must not break the run.
        XCTAssertEqual(SchedulingEngine.currentStreak(for: t, asOf: today, calendar: c), 3)
    }

    func testFloatingWeeklyStreakBreaksOnAMissedWeek() {
        let c = Calendar.current
        let today = c.startOfDay(for: .now)
        let thisWeek = c.dateInterval(of: .weekOfYear, for: today)!.start
        func weekStart(_ weeksAgo: Int) -> Date { c.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)! }

        let t = TaskItem(title: "t", kind: .habit, category: .other,
                         frequency: .floating(.week), startDate: weekStart(6))
        // Did this week and two weeks ago, but missed last week.
        for w in [0, 2] {
            t.completions = (t.completions ?? []) + [Completion(scheduledDate: weekStart(w), status: .done, task: t)]
        }
        // The missed week (1) breaks the run right after the current week → 1.
        XCTAssertEqual(SchedulingEngine.currentStreak(for: t, asOf: today, calendar: c), 1)
    }

    func testFloatingBelongsInTodayLingersOnlyOnTheCompletionDay() {
        let c = Calendar.current
        let today = c.startOfDay(for: .now)
        let weekStart = c.dateInterval(of: .weekOfYear, for: today)!.start
        let t = TaskItem(title: "t", kind: .chore, category: .home, frequency: .floating(.week),
                         startDate: c.date(byAdding: .day, value: -40, to: today)!)
        // Outstanding → shows.
        XCTAssertTrue(SchedulingEngine.belongsInToday(t, on: today, calendar: c))
        // Completed today → still shows, so the row lingers (undoable) until midnight.
        let done = Completion(scheduledDate: weekStart, status: .done, task: t)
        t.completions = [done]
        XCTAssertTrue(SchedulingEngine.belongsInToday(t, on: today, calendar: c))
        // Completed earlier in the period (logged yesterday) → rolled off Today.
        done.loggedAt = c.date(byAdding: .day, value: -1, to: today)!
        XCTAssertFalse(SchedulingEngine.belongsInToday(t, on: today, calendar: c))
    }

    func testDayScheduledCompletedTaskStillBelongsInToday() {
        let c = Calendar.current
        let today = c.startOfDay(for: .now)
        let t = TaskItem(title: "t", kind: .habit, category: .health, frequency: .daily,
                         startDate: c.date(byAdding: .day, value: -5, to: today)!)
        t.completions = [Completion(scheduledDate: today, status: .done, task: t)]
        XCTAssertTrue(SchedulingEngine.belongsInToday(t, on: today, calendar: c),
                      "a finished day-scheduled task stays in Today until the day rolls over")
    }

    func testNotScheduledBeforeStartDate() {
        let t = task(.daily, start: date(2026, 6, 1))
        XCTAssertFalse(SchedulingEngine.isScheduled(t, on: date(2026, 5, 31), calendar: cal))
        XCTAssertTrue(SchedulingEngine.isScheduled(t, on: date(2026, 6, 1), calendar: cal))
    }

    func testArchivedTaskHasNoOccurrences() {
        let t = task(.daily, start: date(2026, 1, 1), archived: true)
        let occ = SchedulingEngine.occurrences(
            for: t, in: DateInterval(start: date(2026, 1, 1), end: date(2026, 1, 7)), calendar: cal)
        XCTAssertTrue(occ.isEmpty)
    }



}
