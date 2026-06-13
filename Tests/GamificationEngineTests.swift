import XCTest
import SwiftData
@testable import HabitsAndChores

@MainActor
final class GamificationEngineTests: XCTestCase {

    // MARK: - Pure level math (no SwiftData needed)

    func testCumulativePointsCurve() {
        XCTAssertEqual(GamificationEngine.cumulativePoints(forLevel: 1), 0)
        XCTAssertEqual(GamificationEngine.cumulativePoints(forLevel: 2), 100)
        XCTAssertEqual(GamificationEngine.cumulativePoints(forLevel: 3), 300)
        XCTAssertEqual(GamificationEngine.cumulativePoints(forLevel: 5), 1000)
    }

    func testLevelForPoints() {
        XCTAssertEqual(GamificationEngine.level(forPoints: 0), 1)
        XCTAssertEqual(GamificationEngine.level(forPoints: 99), 1)
        XCTAssertEqual(GamificationEngine.level(forPoints: 100), 2)
        XCTAssertEqual(GamificationEngine.level(forPoints: 299), 2)
        XCTAssertEqual(GamificationEngine.level(forPoints: 300), 3)
        XCTAssertEqual(GamificationEngine.level(forPoints: 1000), 5)
    }

    func testTitlesAndTierTotals() {
        XCTAssertEqual(GamificationEngine.title(forLevel: 1), "Beginner")
        XCTAssertEqual(GamificationEngine.title(forLevel: 5), "Pro")
        let expectedTiers = GamificationEngine.achievements.reduce(0) { $0 + $1.tiers.count }
        XCTAssertEqual(GamificationEngine.totalTiers, expectedTiers)
        XCTAssertGreaterThan(GamificationEngine.totalTiers, 0)
    }

    // MARK: - Summary over real (in-memory) data

    private func makeContext() throws -> ModelContext {
        // Logic tests only — disable CloudKit so the schema loads without entitlements.
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: TaskItem.self, Completion.self, TodoItem.self,
                                           configurations: config)
        return ModelContext(container)
    }

    func testSummaryCountsDoneCompletionsAndPoints() throws {
        let context = try makeContext()
        let habit = TaskItem(title: "Water", kind: .habit, category: .health, frequency: .daily)
        context.insert(habit)
        let cal = Calendar.current
        for offset in 1...3 {
            let day = cal.date(byAdding: .day, value: -offset, to: .now)!
            context.insert(Completion(scheduledDate: day, status: .done, task: habit))
        }
        // One skip should not count toward points.
        context.insert(Completion(scheduledDate: .now, status: .skipped, task: habit))
        try context.save()

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let summary = GamificationEngine.summary(for: tasks)

        XCTAssertEqual(summary.totalCompleted, 3)
        XCTAssertEqual(summary.habitCompleted, 3)
        XCTAssertEqual(summary.choreCompleted, 0)
        XCTAssertEqual(summary.totalPoints, 30)
        XCTAssertEqual(summary.level, GamificationEngine.level(forPoints: 30))
    }

    func testEmptyStoreSummaryIsZero() throws {
        let context = try makeContext()
        let summary = GamificationEngine.summary(for: try context.fetch(FetchDescriptor<TaskItem>()))
        XCTAssertEqual(summary.totalCompleted, 0)
        XCTAssertEqual(summary.totalPoints, 0)
        XCTAssertEqual(summary.level, 1)
    }
}
