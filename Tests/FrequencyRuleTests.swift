import XCTest
@testable import HabitsAndChores

final class FrequencyRuleTests: XCTestCase {

    func testConvenienceConstructors() {
        XCTAssertEqual(FrequencyRule.daily.kind, .daily)
        XCTAssertEqual(FrequencyRule.weekly(on: [5, 1, 3]).weekdays, [1, 3, 5], "weekdays are sorted")
        XCTAssertEqual(FrequencyRule.monthly(day: 15).dayOfMonth, 15)
        XCTAssertEqual(FrequencyRule.every(0, .week).interval, 1, "interval clamps to >= 1")
        XCTAssertEqual(FrequencyRule.every(3, .month).unit, .month)
    }

    func testCodableRoundTrip() throws {
        let rules: [FrequencyRule] = [.daily, .weekly(on: [2, 4]), .monthly(day: 9), .every(2, .week)]
        for rule in rules {
            let data = try JSONEncoder().encode(rule)
            let decoded = try JSONDecoder().decode(FrequencyRule.self, from: data)
            XCTAssertEqual(decoded, rule)
        }
    }

    func testLocalizedDescriptionNonEmpty() {
        let rules: [FrequencyRule] = [.daily, .weekly(on: [2]), .monthly(day: 1), .every(2, .day)]
        for rule in rules {
            XCTAssertFalse(rule.localizedDescription.isEmpty)
        }
    }

    func testEveryNWeeksLandsOnAnchorWeekday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!  // a Thursday
        let task = TaskItem(title: "t", kind: .habit, category: .other,
                            frequency: .every(2, .week), startDate: start)
        let occ = SchedulingEngine.occurrences(
            for: task,
            in: DateInterval(start: start, end: cal.date(from: DateComponents(year: 2026, month: 2, day: 28))!),
            calendar: cal)
        // Every occurrence falls on the anchor weekday.
        let anchorWeekday = cal.component(.weekday, from: start)
        XCTAssertTrue(occ.allSatisfy { cal.component(.weekday, from: $0) == anchorWeekday })
        XCTAssertGreaterThanOrEqual(occ.count, 4)
    }
}
