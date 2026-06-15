import XCTest
import SwiftData
@testable import HabitsAndChores

/// Micro-benchmarks for the pure, main-actor computations that run on the task
/// completion path. These profile the *fixable* algorithmic cost (the engines),
/// not the CloudKit-mirrored `save()` or the SwiftUI render — neither of which is
/// observable here (no iCloud / no UI in the test environment; see CLAUDE.md §9).
///
/// Note: `measure {}` baselines live inside the (XcodeGen-generated, uncommitted)
/// `.xcodeproj`, so they don't survive `xcodegen generate` and don't gate CI.
/// Treat these as a local profiling + manual-regression tool — read the ms numbers.
@MainActor
final class PerformanceTests: XCTestCase {

    // Heavy but plausible: a power user with many tasks and ~2 years of history.
    private let taskCount = 80
    private let dayCount = 730

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: TaskItem.self, Completion.self, TodoItem.self,
                                           configurations: config)
        return ModelContext(container)
    }

    /// Builds `taskCount` daily tasks, each with `dayCount` consecutive done
    /// completions, and returns the fetched tasks (as the views see them).
    private func makeLargeDataset() throws -> [TaskItem] {
        let context = try makeContext()
        let cal = Calendar.current
        for i in 0..<taskCount {
            let task = TaskItem(title: "Task \(i)",
                                kind: i.isMultiple(of: 2) ? .habit : .chore,
                                category: .health,
                                frequency: .daily)
            context.insert(task)
            for offset in 0..<dayCount {
                let day = cal.date(byAdding: .day, value: -offset, to: .now)!
                context.insert(Completion(scheduledDate: day, status: .done, task: task))
            }
        }
        try context.save()
        return try context.fetch(FetchDescriptor<TaskItem>())
    }

    /// The full gamification recompute — the heaviest thing on the completion tap
    /// path (per-task streaks, weekly occurrences, and the 16-week perfect-week scan).
    func testSummaryPerformanceLargeDataset() throws {
        let tasks = try makeLargeDataset()
        // Sanity-check the dataset is non-trivial so a future change can't quietly
        // turn this into a benchmark of an empty store.
        XCTAssertEqual(tasks.count, taskCount)
        XCTAssertGreaterThan(GamificationEngine.summary(for: tasks).totalCompleted, taskCount)

        measure { _ = GamificationEngine.summary(for: tasks) }
    }

    /// Occurrence generation over a one-year window across all tasks (the weekly-goal
    /// and perfect-week passes both lean on this).
    func testOccurrenceGenerationPerformance() throws {
        let tasks = try makeLargeDataset()
        let cal = Calendar.current
        let span = DateInterval(start: cal.date(byAdding: .year, value: -1, to: .now)!, end: .now)

        measure {
            for task in tasks {
                _ = SchedulingEngine.occurrences(for: task, in: span, calendar: cal)
            }
        }
    }

    /// Current + longest streak across all tasks (called once per task per summary).
    func testStreakPerformance() throws {
        let tasks = try makeLargeDataset()
        let cal = Calendar.current

        measure {
            for task in tasks {
                _ = SchedulingEngine.currentStreak(for: task, asOf: .now, calendar: cal)
                _ = SchedulingEngine.longestStreak(for: task, asOf: .now, calendar: cal)
            }
        }
    }
}
