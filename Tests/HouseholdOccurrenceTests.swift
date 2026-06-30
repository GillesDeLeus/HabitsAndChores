import XCTest
import CloudKit
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
                                createdAt: .now, assignees: ["Sam"], completedByMembers: [], isDone: false)
        let draft = ChoreDraft(chore)
        XCTAssertEqual(draft.title, "Bins")
        XCTAssertEqual(draft.details, "out front")
        XCTAssertEqual(draft.kind, .chore)
        XCTAssertEqual(draft.category, .home)
        XCTAssertEqual(draft.symbolName, "trash.fill")
        XCTAssertEqual(draft.assignees, ["Sam"])
        XCTAssertEqual(draft.frequency, .weekly(on: [3]))
        XCTAssertFalse(draft.isTodo)
    }

    func testChoreDraftCopiesTodoFields() {
        let due = date(2026, 6, 20, 9)
        let remind = date(2026, 6, 19, 8)
        let chore = SharedChore(id: "2", title: "Pay rent", details: "",
                                kindRaw: TaskKind.chore.rawValue, categoryRaw: TaskCategory.finance.rawValue,
                                frequency: .daily, symbolName: "creditcard.fill", colorHue: 0.2,
                                createdAt: .now, assignees: ["Alex"], completedByMembers: [], isDone: false,
                                isTodo: true, dueDate: due, priorityRaw: TodoPriority.high.rawValue,
                                reminderModeRaw: TodoReminderMode.atTime.rawValue, reminderDate: remind,
                                reminderOffset: 0)
        let draft = ChoreDraft(chore)
        XCTAssertTrue(draft.isTodo)
        XCTAssertEqual(draft.dueDate, due)
        XCTAssertEqual(draft.priority, .high)
        XCTAssertEqual(draft.todoReminderMode, .atTime)
        XCTAssertEqual(draft.reminderDate, remind)
        XCTAssertEqual(draft.assignees, ["Alex"])
    }

    // MARK: To-do vs recurring completion key

    func testTodoOccurrenceUsesSentinel() {
        let todo = SharedChore(id: "3", title: "X", details: "",
                               kindRaw: TaskKind.chore.rawValue, categoryRaw: TaskCategory.other.rawValue,
                               frequency: .daily, symbolName: "checklist", colorHue: 0.5,
                               createdAt: .now, assignees: [], completedByMembers: [], isDone: false, isTodo: true)
        XCTAssertEqual(HouseholdService.occurrence(for: todo), HouseholdService.todoOccurrence)
    }

    func testRecurringOccurrenceUsesFrequency() {
        let chore = SharedChore(id: "4", title: "X", details: "",
                                kindRaw: TaskKind.chore.rawValue, categoryRaw: TaskCategory.other.rawValue,
                                frequency: .daily, symbolName: "checklist", colorHue: 0.5,
                                createdAt: date(2026, 6, 1), assignees: [], completedByMembers: [], isDone: false)
        let result = HouseholdService.occurrence(for: chore, asOf: date(2026, 6, 13, 14), calendar: cal)
        XCTAssertEqual(result, date(2026, 6, 13))
    }

    // MARK: Rotation

    func testRotationAdvancesOnCompletion() {
        let names = ["Alex", "Bo", "Sam"]
        XCTAssertEqual(HouseholdService.rotatedAssignee(names: names, current: "Alex", done: true), "Bo")
        XCTAssertEqual(HouseholdService.rotatedAssignee(names: names, current: "Sam", done: true), "Alex") // wraps
    }

    func testRotationRetreatsOnUncompletion() {
        let names = ["Alex", "Bo", "Sam"]
        XCTAssertEqual(HouseholdService.rotatedAssignee(names: names, current: "Bo", done: false), "Alex")
        XCTAssertEqual(HouseholdService.rotatedAssignee(names: names, current: "Alex", done: false), "Sam") // wraps
        // Advance then retreat returns to the start (toggling is symmetric).
        let advanced = HouseholdService.rotatedAssignee(names: names, current: "Bo", done: true)
        XCTAssertEqual(HouseholdService.rotatedAssignee(names: names, current: advanced, done: false), "Bo")
    }

    func testRotationFromUnassignedAndEmpty() {
        XCTAssertEqual(HouseholdService.rotatedAssignee(names: ["Alex", "Bo"], current: nil, done: true), "Alex")
        XCTAssertNil(HouseholdService.rotatedAssignee(names: [], current: "Alex", done: true))
    }

    // MARK: Today visibility (mine / unassigned / just-completed)

    func testMineForTodayShowsMineAndUnassigned() {
        XCTAssertTrue(HouseholdService.isMineForToday(assignees: ["Alex"], completedByMembers: [], myName: "Alex"))
        XCTAssertTrue(HouseholdService.isMineForToday(assignees: [], completedByMembers: [], myName: "Alex"),
                      "unassigned chores are up for grabs")
        XCTAssertFalse(HouseholdService.isMineForToday(assignees: ["Bo"], completedByMembers: [], myName: "Alex"),
                       "someone else's open chore isn't on my Today")
    }

    func testMineForTodayLingersForAChoreIJustCompletedAfterRotation() {
        // A rotating chore I completed: assignee has already rotated to Bo, but I'm
        // in the completer set for this occurrence, so it stays on my Today (struck through).
        XCTAssertTrue(HouseholdService.isMineForToday(assignees: ["Bo"], completedByMembers: ["Alex"], myName: "Alex"))
        // Once the occurrence resets (no completers) it's no longer mine — it's Bo's.
        XCTAssertFalse(HouseholdService.isMineForToday(assignees: ["Bo"], completedByMembers: [], myName: "Alex"))
        // A chore someone *else* completed doesn't show on my Today via this clause.
        XCTAssertFalse(HouseholdService.isMineForToday(assignees: ["Sam"], completedByMembers: ["Bo"], myName: "Alex"))
    }

    // MARK: Per-person un-complete

    private func completion(choreID: String, date: Date, by: String) -> CKRecord {
        let rec = CKRecord(recordType: "SharedCompletion")
        rec["choreID"] = choreID
        rec["date"] = date
        rec["completedBy"] = by
        return rec
    }

    func testUnCompleteRemovesOnlyMyCompletion() {
        // Two members completed the same occurrence; when Alex un-checks, only Alex's
        // record is targeted for deletion — Bo's tick survives (per-person check-off).
        let occ = date(2026, 6, 15)
        let records = [
            completion(choreID: "c1", date: occ, by: "Alex"),
            completion(choreID: "c1", date: date(2026, 6, 15, 9), by: "Bo"), // same day, diff time
            completion(choreID: "c1", date: date(2026, 6, 14), by: "Alex"),  // earlier occurrence
            completion(choreID: "c2", date: occ, by: "Alex"),                // different chore
        ]
        let targets = HouseholdService.completionsToRemove(
            from: records, choreRecordName: "c1", occurrence: occ, by: "Alex", calendar: cal)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?["completedBy"] as? String, "Alex")
        XCTAssertEqual(targets.first?["choreID"] as? String, "c1")
    }

    // MARK: Conflict-merge (member name / avatar maps)

    func testMergedMapAddsToEmpty() {
        let map = HouseholdService.mergedMap(nil, setting: "userA", to: "Alex") as [String: String]
        XCTAssertEqual(map, ["userA": "Alex"])
    }

    func testMergedMapPreservesConcurrentEntriesOnConflict() throws {
        // Simulate the conflict path: the server record already has another member's
        // entry; re-merging my key must keep theirs (not clobber the whole map).
        let server = try JSONEncoder().encode(["userB": "Bo"])
        let merged = HouseholdService.mergedMap(server, setting: "userA", to: "Alex") as [String: String]
        XCTAssertEqual(merged, ["userA": "Alex", "userB": "Bo"])
    }

    func testMergedMapOverwritesOwnKeyAndRemovesOnNil() throws {
        let base = try JSONEncoder().encode(["userA": "Alex"])
        let updated = HouseholdService.mergedMap(base, setting: "userA", to: "Alexandra") as [String: String]
        XCTAssertEqual(updated["userA"], "Alexandra")
        let removed = HouseholdService.mergedMap(base, setting: "userA", to: String?.none) as [String: String]
        XCTAssertNil(removed["userA"])
    }

    func testMergedMapWorksForAvatarConfigValues() throws {
        // The avatar map is [String: AvatarConfig]; the same merge keeps a co-member's
        // avatar while adding mine.
        var mine = AvatarConfig(); mine.hair = 3
        var theirs = AvatarConfig(); theirs.hair = 5
        let server = try JSONEncoder().encode(["userB": theirs])
        let merged = HouseholdService.mergedMap(server, setting: "userA", to: mine) as [String: AvatarConfig]
        XCTAssertEqual(merged["userA"], mine)
        XCTAssertEqual(merged["userB"], theirs)
    }
}
