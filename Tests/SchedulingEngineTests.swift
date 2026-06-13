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
