import XCTest
@testable import HabitsAndChores

/// Pure-logic coverage for the shared-household value types: the to-do scheduling
/// predicate, the reminder discriminator, the recurring-occurrence keying edge
/// cases, and the `ChoreDraft` round-trip the offline outbox depends on.
final class SharedChoreTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func chore(isTodo: Bool = false, frequency: FrequencyRule = .daily,
                       createdAt: Date = .now) -> SharedChore {
        SharedChore(id: "1", title: "X", details: "",
                    kindRaw: TaskKind.chore.rawValue, categoryRaw: TaskCategory.home.rawValue,
                    frequency: frequency, symbolName: "house.fill", colorHue: 0.1,
                    createdAt: createdAt, assignee: nil, isDone: false, completedBy: nil,
                    isTodo: isTodo)
    }

    // MARK: - isScheduledTodo

    func testScheduledTodoSurfacesOnOrBefore() {
        var c = chore(isTodo: true)
        c.scheduledDate = date(2026, 6, 15)
        XCTAssertTrue(c.isScheduledTodo(onOrBefore: date(2026, 6, 15), calendar: cal))
        XCTAssertTrue(c.isScheduledTodo(onOrBefore: date(2026, 6, 18), calendar: cal))
        XCTAssertFalse(c.isScheduledTodo(onOrBefore: date(2026, 6, 14), calendar: cal))
    }

    func testScheduledTodoFalseWhenDoneRecurringOrUnscheduled() {
        var c = chore(isTodo: true)
        XCTAssertFalse(c.isScheduledTodo(onOrBefore: date(2026, 6, 15), calendar: cal),
                       "no scheduledDate")
        c.scheduledDate = date(2026, 6, 10)
        c.isDone = true
        XCTAssertFalse(c.isScheduledTodo(onOrBefore: date(2026, 6, 15), calendar: cal),
                       "done to-dos drop off")
        // A recurring chore (not a to-do) never surfaces through this predicate.
        var recurring = chore(isTodo: false)
        recurring.scheduledDate = date(2026, 6, 10)
        XCTAssertFalse(recurring.isScheduledTodo(onOrBefore: date(2026, 6, 15), calendar: cal))
    }

    // MARK: - hasReminder (discriminated by isTodo)

    func testHasReminderForRecurringChore() {
        var c = chore(isTodo: false)
        XCTAssertFalse(c.hasReminder)
        c.reminderHour = 8
        XCTAssertFalse(c.hasReminder, "hour without minute is not a reminder")
        c.reminderMinute = 0
        XCTAssertTrue(c.hasReminder)
    }

    func testHasReminderForTodoUsesMode() {
        var c = chore(isTodo: true)
        // A to-do ignores the recurring hour/minute and looks at its reminder mode.
        c.reminderHour = 8
        c.reminderMinute = 0
        XCTAssertFalse(c.hasReminder, "to-do reminder is driven by mode, not hour/minute")
        c.reminderModeRaw = TodoReminderMode.atTime.rawValue
        XCTAssertTrue(c.hasReminder)
    }

    // MARK: - occurrence keying

    func testTodoUsesSentinelOccurrence() {
        let c = chore(isTodo: true)
        XCTAssertEqual(HouseholdService.occurrence(for: c), HouseholdService.todoOccurrence)
    }

    func testWeeklyWithNoWeekdaysFallsBackToToday() {
        // A weekly rule with an empty weekday set has no matching day → keys to today.
        let occ = HouseholdService.currentOccurrence(for: .weekly(on: []),
                                                     asOf: date(2026, 6, 17, 14), calendar: cal)
        XCTAssertEqual(occ, date(2026, 6, 17))
    }

    func testFloatingKeysToPeriodStart() {
        // Floating weekly keys every day of the week to that week's start, so the
        // shared chore stays done until the next period.
        let occMid = HouseholdService.currentOccurrence(for: .floating(.week),
                                                        asOf: date(2026, 6, 17), calendar: cal)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: date(2026, 6, 17))!.start
        XCTAssertEqual(occMid, weekStart)
    }

    // MARK: - ChoreDraft persistence (offline outbox)

    func testChoreDraftCodableRoundTripPreservesAllFields() throws {
        var draft = ChoreDraft()
        draft.title = "Pay rent"
        draft.details = "first of month"
        draft.kind = .chore
        draft.category = .finance
        draft.symbolName = "creditcard.fill"
        draft.colorHue = 0.33
        draft.frequency = .monthly(day: 1)
        draft.assignee = "Sam"
        draft.isTodo = true
        draft.dueDate = date(2026, 7, 1, 9)
        draft.scheduledDate = date(2026, 6, 30)
        draft.priority = .high
        draft.todoReminderMode = .beforeDue
        draft.reminderOffset = 3600
        draft.reminderHour = 8
        draft.reminderMinute = 30
        draft.rotates = true

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(ChoreDraft.self, from: data)

        XCTAssertEqual(decoded.title, draft.title)
        XCTAssertEqual(decoded.details, draft.details)
        XCTAssertEqual(decoded.kind, draft.kind)
        XCTAssertEqual(decoded.category, draft.category)
        XCTAssertEqual(decoded.symbolName, draft.symbolName)
        XCTAssertEqual(decoded.colorHue, draft.colorHue)
        XCTAssertEqual(decoded.frequency, draft.frequency)
        XCTAssertEqual(decoded.assignee, draft.assignee)
        XCTAssertEqual(decoded.isTodo, draft.isTodo)
        XCTAssertEqual(decoded.dueDate, draft.dueDate)
        XCTAssertEqual(decoded.scheduledDate, draft.scheduledDate)
        XCTAssertEqual(decoded.priority, draft.priority)
        XCTAssertEqual(decoded.todoReminderMode, draft.todoReminderMode)
        XCTAssertEqual(decoded.reminderOffset, draft.reminderOffset)
        XCTAssertEqual(decoded.reminderHour, draft.reminderHour)
        XCTAssertEqual(decoded.reminderMinute, draft.reminderMinute)
        XCTAssertEqual(decoded.rotates, draft.rotates)
    }

    func testDraftFromChoreThenBackPreservesIdentity() {
        // SharedChore → ChoreDraft is exercised in HouseholdOccurrenceTests; here we
        // confirm the draft of a rotating recurring chore keeps the rotate flag.
        var c = chore(isTodo: false, frequency: .weekly(on: [2]))
        c.rotates = true
        c.assignee = "Bo"
        let draft = ChoreDraft(c)
        XCTAssertTrue(draft.rotates)
        XCTAssertEqual(draft.assignee, "Bo")
        XCTAssertEqual(draft.frequency, .weekly(on: [2]))
    }
}
