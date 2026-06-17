import XCTest
import SwiftData
@testable import HabitsAndChores

/// Covers the parts of `GamificationEngine.Summary` and the tiered-badge math that
/// `GamificationEngineTests` left out: distinct categories, early-bird detection,
/// perfect weeks, weekly progress, and the `Achievement` tier predicates.
@MainActor
final class GamificationSummaryTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: TaskItem.self, Completion.self, TodoItem.self,
                                               configurations: config))
    }

    private let cal = Calendar.current

    // MARK: - Summary aggregates over real data

    func testDistinctCategoriesCountsOnlyCategoriesWithADoneCompletion() throws {
        let ctx = try makeContext()
        let health = TaskItem(title: "Run", kind: .habit, category: .health, frequency: .daily)
        let home = TaskItem(title: "Dishes", kind: .chore, category: .home, frequency: .daily)
        let finance = TaskItem(title: "Budget", kind: .chore, category: .finance, frequency: .daily)
        [health, home, finance].forEach(ctx.insert)
        // Done in health + home; finance only has a *skip* → shouldn't count.
        ctx.insert(Completion(scheduledDate: .now, status: .done, task: health))
        ctx.insert(Completion(scheduledDate: .now, status: .done, task: home))
        ctx.insert(Completion(scheduledDate: .now, status: .skipped, task: finance))
        try ctx.save()

        let s = GamificationEngine.summary(for: try ctx.fetch(FetchDescriptor<TaskItem>()))
        XCTAssertEqual(s.distinctCategories, 2)
    }

    func testEarlyBirdCountsCompletionsLoggedBefore9AM() throws {
        let ctx = try makeContext()
        let t = TaskItem(title: "Meditate", kind: .habit, category: .health, frequency: .daily)
        ctx.insert(t)
        let today = cal.startOfDay(for: .now)
        // 7 AM → early bird; 10 AM → not.
        let early = Completion(scheduledDate: today, status: .done, task: t)
        early.loggedAt = cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
        let late = Completion(scheduledDate: cal.date(byAdding: .day, value: -1, to: today)!,
                              status: .done, task: t)
        late.loggedAt = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        ctx.insert(early); ctx.insert(late)
        try ctx.save()

        let s = GamificationEngine.summary(for: try ctx.fetch(FetchDescriptor<TaskItem>()))
        XCTAssertEqual(s.earlyBirdCount, 1)
        XCTAssertEqual(s.totalCompleted, 2)
    }

    func testPerfectWeekCountsAFullyCompletedPriorWeek() throws {
        let ctx = try makeContext()
        let today = cal.startOfDay(for: .now)
        // Start the task well before so it's scheduled every day of last week.
        let start = cal.date(byAdding: .day, value: -120, to: today)!
        let t = TaskItem(title: "Stretch", kind: .habit, category: .health, frequency: .daily,
                         startDate: start)
        ctx.insert(t)

        // Last full week: the week before this one.
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)!
        let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start)!
        for offset in 0..<7 {
            let day = cal.date(byAdding: .day, value: offset, to: lastWeekStart)!
            ctx.insert(Completion(scheduledDate: day, status: .done, task: t))
        }
        try ctx.save()

        let s = GamificationEngine.summary(for: try ctx.fetch(FetchDescriptor<TaskItem>()))
        XCTAssertEqual(s.perfectWeekCount, 1,
                       "exactly one prior week is fully completed; the others are scheduled-but-undone")
    }

    func testWeeklyProgressReflectsThisWeekDoneOverScheduled() throws {
        let ctx = try makeContext()
        let today = cal.startOfDay(for: .now)
        let t = TaskItem(title: "Walk", kind: .habit, category: .health, frequency: .daily,
                         startDate: cal.date(byAdding: .day, value: -30, to: today)!)
        ctx.insert(t)
        ctx.insert(Completion(scheduledDate: today, status: .done, task: t))
        try ctx.save()

        let s = GamificationEngine.summary(for: try ctx.fetch(FetchDescriptor<TaskItem>()))
        XCTAssertEqual(s.completedThisWeek, 1)
        XCTAssertGreaterThanOrEqual(s.scheduledThisWeek, 1)
        XCTAssertGreaterThan(s.weeklyProgress, 0)
        XCTAssertLessThanOrEqual(s.weeklyProgress, 1)
    }

    func testEmptyWeeklyProgressIsZeroNotNaN() throws {
        let ctx = try makeContext()
        let s = GamificationEngine.summary(for: try ctx.fetch(FetchDescriptor<TaskItem>()))
        XCTAssertEqual(s.weeklyProgress, 0, "no scheduled occurrences → 0, not a divide-by-zero NaN")
    }

    // MARK: - Achievement tier math (pure, over a hand-built Summary)

    private func summary(totalCompleted: Int) -> GamificationEngine.Summary {
        var s = GamificationEngine.Summary()
        s.totalCompleted = totalCompleted
        return s
    }

    func testTierReachedAndNextGoalProgression() {
        let badge = GamificationEngine.achievements.first { $0.id == "task_completer" }!
        // tiers [1, 10, 50, 100, 250]
        XCTAssertEqual(badge.tierReached(summary(totalCompleted: 0)), 0)
        XCTAssertEqual(badge.nextGoal(summary(totalCompleted: 0)), 1)
        XCTAssertEqual(badge.tierReached(summary(totalCompleted: 50)), 3)
        XCTAssertEqual(badge.nextGoal(summary(totalCompleted: 50)), 100)
        XCTAssertFalse(badge.isMaxed(summary(totalCompleted: 50)))
    }

    func testMaxedBadgeHasNoNextGoal() {
        let badge = GamificationEngine.achievements.first { $0.id == "task_completer" }!
        let maxed = summary(totalCompleted: 1000)
        XCTAssertEqual(badge.tierReached(maxed), badge.tiers.count)
        XCTAssertTrue(badge.isMaxed(maxed))
        XCTAssertNil(badge.nextGoal(maxed))
        XCTAssertEqual(badge.value(maxed), 1000)
    }

    func testTiersEarnedSumsAcrossFamiliesAndNeverExceedsTotal() {
        var s = GamificationEngine.Summary()
        s.totalCompleted = 250   // task_completer maxed (5 tiers)
        s.level = 12             // climber maxed (5 tiers)
        let earned = GamificationEngine.tiersEarned(in: s)
        XCTAssertGreaterThanOrEqual(earned, 10)
        XCTAssertLessThanOrEqual(earned, GamificationEngine.totalTiers)
    }

    func testTopLevelTitleIsLegend() {
        XCTAssertEqual(GamificationEngine.title(forLevel: 7), "Master", "last explicit tier")
        XCTAssertEqual(GamificationEngine.title(forLevel: 8), "Legend", "everything past 7 is Legend")
        XCTAssertEqual(GamificationEngine.title(forLevel: 0), "Beginner", "level <= 1 floor")
    }

    // MARK: - AchievementTracker celebrate-once semantics

    func testTrackerCelebratesOnceThenStaysSilent() {
        UserDefaults.standard.removeObject(forKey: "seenBadgeTiers")
        defer { UserDefaults.standard.removeObject(forKey: "seenBadgeTiers") }

        var s = GamificationEngine.Summary()
        s.totalCompleted = 10    // reaches a new tier on Task Completer
        XCTAssertTrue(GamificationEngine.tiersEarned(in: s) > 0)
        XCTAssertTrue(AchievementTracker.registerAndCheck(s), "first sighting of a new tier celebrates")
        XCTAssertFalse(AchievementTracker.registerAndCheck(s), "same summary again doesn't re-celebrate")

        s.totalCompleted = 50    // a further tier
        XCTAssertTrue(AchievementTracker.registerAndCheck(s), "a newly reached tier celebrates again")
    }
}
