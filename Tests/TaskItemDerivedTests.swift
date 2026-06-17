import XCTest
@testable import HabitsAndChores

/// Per-day completion lookups on `TaskItem` (used everywhere the UI asks "is this
/// done today?") plus the raw-value fallbacks that protect against corrupt stored
/// enums. `ModelTests` covers the constructor defaults; this covers the lookups.
final class TaskItemDerivedTests: XCTestCase {

    // `Completion.init` normalizes `scheduledDate` via `Calendar.current`, so day
    // keys here use the same calendar (mixing in a UTC test calendar would shift the
    // stored day by the local UTC offset — exactly the trap StreakTests sidesteps).
    private let cal = Calendar.current

    private func day(_ daysAgo: Int) -> Date {
        cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))!
    }

    private func task() -> TaskItem {
        TaskItem(title: "Walk", kind: .habit, category: .health, frequency: .daily,
                 startDate: day(60))
    }

    func testIsCompletedMatchesOnlyDoneOnThatDay() {
        let t = task()
        t.completions = [Completion(scheduledDate: day(2), status: .done, task: t)]
        XCTAssertTrue(t.isCompleted(on: day(2), calendar: cal))
        XCTAssertFalse(t.isCompleted(on: day(3), calendar: cal), "different day")
    }

    func testIsCompletedIgnoresSkipped() {
        let t = task()
        t.completions = [Completion(scheduledDate: day(2), status: .skipped, task: t)]
        XCTAssertFalse(t.isCompleted(on: day(2), calendar: cal), "a skip is not a completion")
    }

    func testCompletionReturnsEitherStatusForTheDay() {
        let t = task()
        let skip = Completion(scheduledDate: day(2), status: .skipped, task: t)
        t.completions = [skip]
        // `completion(on:)` returns the entry regardless of status (done *or* skipped).
        XCTAssertEqual(t.completion(on: day(2), calendar: cal)?.status, .skipped)
        XCTAssertNil(t.completion(on: day(3), calendar: cal))
    }

    func testNilCompletionsAreSafe() {
        let t = task()
        t.completions = nil
        XCTAssertFalse(t.isCompleted(on: day(0), calendar: cal))
        XCTAssertNil(t.completion(on: day(0), calendar: cal))
    }

    func testCorruptRawValuesFallBackToDefaults() {
        let t = task()
        t.kindRaw = "not-a-kind"
        t.categoryRaw = "not-a-category"
        XCTAssertEqual(t.kind, .chore, "unknown kind → chore")
        XCTAssertEqual(t.category, .other, "unknown category → other")
    }

    func testHasReminderRequiresBothComponents() {
        let t = task()
        XCTAssertFalse(t.hasReminder)
        t.reminderHour = 8
        XCTAssertFalse(t.hasReminder, "hour alone is not a reminder")
        t.reminderMinute = 30
        XCTAssertTrue(t.hasReminder)
    }
}
