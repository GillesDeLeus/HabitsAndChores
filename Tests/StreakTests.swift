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
