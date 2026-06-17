import XCTest
import SwiftData
@testable import HabitsAndChores

@MainActor
final class StreakTests: XCTestCase {

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: TaskItem.self, Completion.self, TodoItem.self,
                                               configurations: config))
    }

    private let cal = Calendar.current

    private func dailyTask(in ctx: ModelContext) -> TaskItem {
        let start = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now))!
        let t = TaskItem(title: "Water", kind: .habit, category: .health, frequency: .daily, startDate: start)
        ctx.insert(t)
        return t
    }

    private func addDone(_ task: TaskItem, daysAgo: Int, in ctx: ModelContext) {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))!
        ctx.insert(Completion(scheduledDate: day, status: .done, task: task))
    }

    private func addSkipped(_ task: TaskItem, daysAgo: Int, in ctx: ModelContext) {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))!
        ctx.insert(Completion(scheduledDate: day, status: .skipped, task: task))
    }

    /// A skipped day is neutral: it neither extends nor breaks the run, so a done
    /// day on either side of a skip stays connected. Guards the `CompletionIndex`
    /// refactor, which recomputed done/skipped as separate sets.
    func testSkippedDayIsNeutralInStreak() throws {
        let ctx = try context()
        let task = dailyTask(in: ctx)
        addDone(task, daysAgo: 0, in: ctx)
        addSkipped(task, daysAgo: 1, in: ctx)   // neutral
        addDone(task, daysAgo: 2, in: ctx)
        try ctx.save()
        XCTAssertEqual(SchedulingEngine.currentStreak(for: task), 2,
                       "two done days bridged by a skip count as a streak of 2")
    }

    /// When a day has both a done and a skipped completion, done wins (matches the
    /// previous `isCompleted`-first ordering).
    func testDoneWinsOverSkippedOnSameDay() throws {
        let ctx = try context()
        let task = dailyTask(in: ctx)
        addSkipped(task, daysAgo: 0, in: ctx)
        addDone(task, daysAgo: 0, in: ctx)
        try ctx.save()
        XCTAssertEqual(SchedulingEngine.currentStreak(for: task), 1)
    }

    func testCurrentStreakCountsConsecutiveDays() throws {
        let ctx = try context()
        let task = dailyTask(in: ctx)
        addDone(task, daysAgo: 0, in: ctx)
        addDone(task, daysAgo: 1, in: ctx)
        addDone(task, daysAgo: 2, in: ctx)
        try ctx.save()
        XCTAssertEqual(SchedulingEngine.currentStreak(for: task), 3)
    }

    func testMissBreaksCurrentStreak() throws {
        let ctx = try context()
        let task = dailyTask(in: ctx)
        addDone(task, daysAgo: 0, in: ctx)
        addDone(task, daysAgo: 1, in: ctx)
        // day 2 missed (no completion)
        addDone(task, daysAgo: 3, in: ctx)
        try ctx.save()
        XCTAssertEqual(SchedulingEngine.currentStreak(for: task), 2)
    }

    /// The calendar row computes the streak `asOf` the day it's showing, so a run
    /// ending on a past day reads as that day's streak — not a today-relative number
    /// (which is what made the count look "random" when toggling other days).
    func testCurrentStreakIsRelativeToAsOfDay() throws {
        let ctx = try context()
        let task = dailyTask(in: ctx)
        addDone(task, daysAgo: 5, in: ctx)
        addDone(task, daysAgo: 6, in: ctx)
        addDone(task, daysAgo: 7, in: ctx)
        try ctx.save()
        // As of today the run isn't current (there's a gap since 5 days ago).
        XCTAssertEqual(SchedulingEngine.currentStreak(for: task), 0)
        // As of 5 days ago, that run of 3 *is* the current streak — what the row shows.
        let fiveDaysAgo = cal.date(byAdding: .day, value: -5, to: cal.startOfDay(for: .now))!
        XCTAssertEqual(SchedulingEngine.currentStreak(for: task, asOf: fiveDaysAgo), 3)
    }

    func testLongestStreakFindsBestRun() throws {
        let ctx = try context()
        let task = dailyTask(in: ctx)
        // run of 3
        addDone(task, daysAgo: 5, in: ctx)
        addDone(task, daysAgo: 6, in: ctx)
        addDone(task, daysAgo: 7, in: ctx)
        // separate run of 2 ending today
        addDone(task, daysAgo: 0, in: ctx)
        addDone(task, daysAgo: 1, in: ctx)
        try ctx.save()
        XCTAssertEqual(SchedulingEngine.longestStreak(for: task), 3)
    }
}
