import XCTest
@testable import HabitsAndChores

/// Covers the household-chore contribution to gamification: shared completions the
/// current user made must earn points, badge progress (counts, categories, early
/// bird), streaks, and weekly-goal progress exactly like personal tasks. Pure value
/// inputs (`GamificationEngine.SharedChoreStat`), no CloudKit or SwiftData needed.
@MainActor
final class SharedGamificationTests: XCTestCase {

    private let cal = Calendar.current

    private func stat(kind: TaskKind = .chore,
                      category: TaskCategory = .home,
                      frequency: FrequencyRule = .daily,
                      anchor: Date,
                      completions: [(occurrence: Date, loggedAt: Date)]) -> GamificationEngine.SharedChoreStat {
        .init(kind: kind, categoryRaw: category.rawValue, frequency: frequency,
              anchor: anchor, myCompletions: completions)
    }

    func testSharedCompletionsAddPointsAndCompletedCount() {
        let today = cal.startOfDay(for: .now)
        let s = GamificationEngine.summary(
            for: [],
            shared: [stat(anchor: cal.date(byAdding: .day, value: -10, to: today)!,
                          completions: [(today, .now),
                                        (cal.date(byAdding: .day, value: -1, to: today)!, .now)])])
        XCTAssertEqual(s.totalCompleted, 2)
        XCTAssertEqual(s.choreCompleted, 2)
        XCTAssertEqual(s.totalPoints, 2 * GamificationEngine.pointsPerCompletion)
    }

    func testSharedAndPersonalCompletionsCombine() {
        // One personal-equivalent (faked as another shared chore) + one shared chore;
        // both should accrue. Using two shared stats keeps the test dependency-free.
        let today = cal.startOfDay(for: .now)
        let anchor = cal.date(byAdding: .day, value: -10, to: today)!
        let s = GamificationEngine.summary(
            for: [],
            shared: [stat(kind: .habit, category: .health, anchor: anchor, completions: [(today, .now)]),
                     stat(kind: .chore, category: .home, anchor: anchor, completions: [(today, .now)])])
        XCTAssertEqual(s.totalCompleted, 2)
        XCTAssertEqual(s.habitCompleted, 1)
        XCTAssertEqual(s.choreCompleted, 1)
        XCTAssertEqual(s.distinctCategories, 2)
    }

    func testSharedEarlyBirdCounted() {
        let today = cal.startOfDay(for: .now)
        let early = cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
        let late = cal.date(bySettingHour: 11, minute: 0, second: 0, of: today)!
        let s = GamificationEngine.summary(
            for: [],
            shared: [stat(anchor: cal.date(byAdding: .day, value: -5, to: today)!,
                          completions: [(today, early),
                                        (cal.date(byAdding: .day, value: -1, to: today)!, late)])])
        XCTAssertEqual(s.earlyBirdCount, 1)
    }

    func testSharedDailyChoreBuildsAStreak() {
        let today = cal.startOfDay(for: .now)
        let anchor = cal.date(byAdding: .day, value: -30, to: today)!
        // Completed today and the previous two days → a current streak of 3.
        let days = (0...2).map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let s = GamificationEngine.summary(
            for: [],
            shared: [stat(frequency: .daily, anchor: anchor,
                          completions: days.map { ($0, Date.now) })])
        XCTAssertEqual(s.bestCurrentStreak, 3)
        XCTAssertGreaterThanOrEqual(s.longestStreak, 3)
    }

    func testSharedChoreFeedsWeeklyProgress() {
        let today = cal.startOfDay(for: .now)
        let anchor = cal.date(byAdding: .day, value: -30, to: today)!
        let s = GamificationEngine.summary(
            for: [],
            shared: [stat(frequency: .daily, anchor: anchor, completions: [(today, .now)])])
        XCTAssertEqual(s.completedThisWeek, 1)
        XCTAssertGreaterThanOrEqual(s.scheduledThisWeek, 1)
        XCTAssertGreaterThan(s.weeklyProgress, 0)
        XCTAssertLessThanOrEqual(s.weeklyProgress, 1)
    }

    func testNoSharedStatsLeavesSummaryUnchanged() {
        // The default `shared: []` must behave exactly like the old single-arg call.
        let a = GamificationEngine.summary(for: [])
        let b = GamificationEngine.summary(for: [], shared: [])
        XCTAssertEqual(a.totalPoints, b.totalPoints)
        XCTAssertEqual(a.totalCompleted, b.totalCompleted)
        XCTAssertEqual(a.weeklyProgress, b.weeklyProgress)
    }
}
