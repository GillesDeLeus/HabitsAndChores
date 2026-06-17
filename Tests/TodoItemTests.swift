import XCTest
@testable import HabitsAndChores

/// Pure-logic coverage for `TodoItem` derived state that the lists and Today view
/// rely on but `ModelTests` didn't reach: scheduling-into-Today, the reminder
/// summary strings, and the category/reminder enum bridges.
final class TodoItemTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: - isScheduled(onOrBefore:)

    func testScheduledSurfacesOnOrBeforeTheDay() {
        let todo = TodoItem(title: "Plan trip")
        todo.scheduledDate = date(2026, 6, 15)
        // Same day and any later day → surfaces in Today.
        XCTAssertTrue(todo.isScheduled(onOrBefore: date(2026, 6, 15, 0), calendar: cal))
        XCTAssertTrue(todo.isScheduled(onOrBefore: date(2026, 6, 20), calendar: cal))
        // Earlier day → not yet.
        XCTAssertFalse(todo.isScheduled(onOrBefore: date(2026, 6, 14), calendar: cal))
    }

    func testScheduledIgnoresTimeOfDay() {
        let todo = TodoItem(title: "x")
        todo.scheduledDate = date(2026, 6, 15, 23)
        // Compared at start-of-day, so an evening schedule still counts on its own day.
        XCTAssertTrue(todo.isScheduled(onOrBefore: date(2026, 6, 15, 1), calendar: cal))
    }

    func testNotScheduledWhenDoneOrUnscheduled() {
        let todo = TodoItem(title: "x")
        XCTAssertFalse(todo.isScheduled(onOrBefore: date(2026, 6, 15), calendar: cal),
                       "no scheduledDate → never in Today")
        todo.scheduledDate = date(2026, 6, 10)
        todo.toggle()   // done
        XCTAssertFalse(todo.isScheduled(onOrBefore: date(2026, 6, 15), calendar: cal),
                       "completed to-dos drop off Today")
    }

    // MARK: - Reminder summary

    func testReminderSummaryPerMode() {
        let todo = TodoItem(title: "x")
        // None → no summary.
        XCTAssertNil(todo.reminderSummary)

        todo.reminderMode = .beforeDue
        todo.reminderOffset = 3600
        XCTAssertEqual(todo.reminderSummary, TodoReminderOffset.label(for: 3600))

        todo.reminderMode = .atTime
        todo.reminderDate = date(2026, 6, 20, 8)
        XCTAssertNotNil(todo.reminderSummary, "atTime renders the fire date")

        todo.reminderMode = .dailyUntilDone
        XCTAssertNotNil(todo.reminderSummary, "daily renders a time-of-day string")
    }

    func testReminderOffsetLabelFallsBackForUnknownOffset() {
        XCTAssertEqual(TodoReminderOffset.label(for: 3600), "1 hour before")
        // An offset not in the preset table still yields a non-empty generic label.
        XCTAssertFalse(TodoReminderOffset.label(for: 42).isEmpty)
    }

    // MARK: - Enum bridges

    func testCategoryGetSetBridge() {
        let todo = TodoItem(title: "x")
        XCTAssertNil(todo.category, "empty raw → no category")
        todo.category = .finance
        XCTAssertEqual(todo.categoryRaw, TaskCategory.finance.rawValue)
        XCTAssertEqual(todo.category, .finance)
        todo.category = nil
        XCTAssertEqual(todo.categoryRaw, "", "clearing maps back to empty string")
        XCTAssertNil(todo.category)
    }

    func testReminderModeGetSetBridgeAndHasReminder() {
        let todo = TodoItem(title: "x")
        XCTAssertEqual(todo.reminderMode, .none)
        XCTAssertFalse(todo.hasReminder)
        todo.reminderMode = .dailyUntilDone
        XCTAssertEqual(todo.reminderModeRaw, TodoReminderMode.dailyUntilDone.rawValue)
        XCTAssertTrue(todo.hasReminder)
    }

    func testCorruptRawValuesFallBackToNone() {
        let todo = TodoItem(title: "x")
        todo.priorityRaw = 999
        todo.reminderModeRaw = -1
        XCTAssertEqual(todo.priority, .none)
        XCTAssertEqual(todo.reminderMode, .none)
    }
}
