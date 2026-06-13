import XCTest
@testable import HabitsAndChores

final class HouseholdOccurrenceTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func occurrence(_ freq: FrequencyRule, asOf: Date, anchor: Date = .now) -> Date {
        HouseholdService.currentOccurrence(for: freq, asOf: asOf, anchor: anchor, calendar: cal)
    }

    // MARK: Daily

    func testDailyIsStartOfToday() {
        let result = occurrence(.daily, asOf: date(2026, 6, 13, 14))
        XCTAssertEqual(result, date(2026, 6, 13))
    }

    // MARK: Weekly

    func testWeeklyReturnsMostRecentMatchingWeekday() {
        // Weekday 2 == Monday.
        let asOf = date(2026, 6, 17, 9) // some mid-week day
        let result = occurrence(.weekly(on: [2]), asOf: asOf)
        XCTAssertEqual(cal.component(.weekday, from: result), 2)
        XCTAssertLessThanOrEqual(result, cal.startOfDay(for: asOf))
        let daysBack = cal.dateComponents([.day], from: result, to: cal.startOfDay(for: asOf)).day ?? 99
        XCTAssertLessThan(daysBack, 7)
    }

    // MARK: Monthly

    func testMonthlyThisMonthWhenPastTheDay() {
        XCTAssertEqual(occurrence(.monthly(day: 15), asOf: date(2026, 6, 20)), date(2026, 6, 15))
    }

    func testMonthlyPreviousMonthWhenBeforeTheDay() {
        XCTAssertEqual(occurrence(.monthly(day: 15), asOf: date(2026, 6, 10)), date(2026, 5, 15))
    }

    func testMonthlyClampsAndFallsBack() {
        // Day 31 on June 20: June clamps to 30 (> 20, not yet), so falls back to May 31.
        XCTAssertEqual(occurrence(.monthly(day: 31), asOf: date(2026, 6, 20)), date(2026, 5, 31))
    }

    // MARK: Every-N (anchored to creation date)

    func testEveryNDaysAlignsToAnchor() {
        let anchor = date(2026, 6, 1)
        // 12 days later, interval 3 -> on an occurrence day.
        XCTAssertEqual(occurrence(.every(3, .day), asOf: date(2026, 6, 13), anchor: anchor), date(2026, 6, 13))
        // 13 days later -> most recent occurrence is day 12 (June 13).
        XCTAssertEqual(occurrence(.every(3, .day), asOf: date(2026, 6, 14), anchor: anchor), date(2026, 6, 13))
    }

    func testEveryNWeeksAlignsToAnchor() {
        let anchor = date(2026, 6, 1)
        // 19 days later, every 2 weeks -> 2 aligned weeks from anchor = June 15.
        XCTAssertEqual(occurrence(.every(2, .week), asOf: date(2026, 6, 20), anchor: anchor), date(2026, 6, 15))
    }

    func testEveryNMonthsAlignsToAnchor() {
        let anchor = date(2026, 1, 10)
        // ~5 months later, every 2 months -> 4 aligned months from anchor = May 10.
        XCTAssertEqual(occurrence(.every(2, .month), asOf: date(2026, 6, 20), anchor: anchor), date(2026, 5, 10))
    }

    func testEveryNBeforeAnchorReturnsAnchor() {
        let anchor = date(2026, 6, 10)
        XCTAssertEqual(occurrence(.every(3, .day), asOf: date(2026, 6, 5), anchor: anchor), date(2026, 6, 10))
    }

    // MARK: ChoreDraft mapping

    func testChoreDraftCopiesChoreFields() {
        let chore = SharedChore(id: "1", title: "Bins", details: "out front",
                                kindRaw: TaskKind.chore.rawValue, categoryRaw: TaskCategory.home.rawValue,
                                frequency: .weekly(on: [3]), symbolName: "trash.fill", colorHue: 0.1,
                                createdAt: .now, assignee: "Sam", isDone: false, completedBy: nil)
        let draft = ChoreDraft(chore)
        XCTAssertEqual(draft.title, "Bins")
        XCTAssertEqual(draft.details, "out front")
        XCTAssertEqual(draft.kind, .chore)
        XCTAssertEqual(draft.category, .home)
        XCTAssertEqual(draft.symbolName, "trash.fill")
        XCTAssertEqual(draft.assignee, "Sam")
        XCTAssertEqual(draft.frequency, .weekly(on: [3]))
    }
}
