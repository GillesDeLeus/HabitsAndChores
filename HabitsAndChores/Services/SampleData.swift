import Foundation
import SwiftData

/// Inserts a realistic set of tasks plus ~4 weeks of completion history so the
/// Today, Calendar and Stats screens have something to show. Intended for manual
/// testing only — surfaced through the DEBUG-only Developer section in Settings.
@MainActor
enum SampleData {

    /// Human-readable outcome of a seed/wipe, shown to the tester in an alert.
    enum Result { case message(String) }

    /// Seeds sample tasks and history. Does nothing if the store already has tasks,
    /// unless `reset` is true (which wipes existing data first).
    @discardableResult
    static func populate(_ context: ModelContext, reset: Bool = false, calendar: Calendar = .current) -> Result {
        if reset { wipe(context) }

        let existing = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        guard existing.isEmpty else {
            return .message("Store already has \(existing.count) task(s). Tap “Delete all data” first to reseed.")
        }

        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -30, to: today) ?? today

        let tasks: [TaskItem] = [
            TaskItem(title: "Drink water", details: "8 glasses a day.", kind: .habit, category: .health,
                     frequency: .daily, symbolName: "drop.fill", colorHue: 0.55, startDate: start,
                     reminderHour: 9, reminderMinute: 0),
            TaskItem(title: "Morning walk", details: "30 minutes outside.", kind: .habit, category: .health,
                     frequency: .daily, symbolName: "figure.walk", colorHue: 0.33, startDate: start),
            TaskItem(title: "Take out the trash", kind: .chore, category: .home,
                     frequency: .weekly(on: [3, 6]), symbolName: "trash.fill", colorHue: 0.08, startDate: start),
            TaskItem(title: "Vacuum living room", kind: .chore, category: .home,
                     frequency: .weekly(on: [7]), symbolName: "house.fill", colorHue: 0.62, startDate: start),
            TaskItem(title: "Walk the dog", details: "Evening loop around the block.", kind: .chore,
                     category: .pets, frequency: .every(2, .day), symbolName: "pawprint.fill",
                     colorHue: 0.1, startDate: start),
            TaskItem(title: "Review budget", kind: .chore, category: .finance,
                     frequency: .monthly(day: 1), symbolName: "chart.pie.fill", colorHue: 0.13, startDate: start),
            TaskItem(title: "Read 20 minutes", kind: .habit, category: .productivity,
                     frequency: .daily, symbolName: "book.fill", colorHue: 0.75, startDate: start),
        ]
        for t in tasks { context.insert(t) }

        // Build completion history. Mark most past occurrences done, with a few
        // skips and the occasional miss, so streaks and stats look organic.
        // Today's occurrences are left open so the Today tab still has work to do.
        var completionCount = 0
        let history = DateInterval(start: start, end: today)
        for (index, task) in tasks.enumerated() {
            for date in SchedulingEngine.occurrences(for: task, in: history, calendar: calendar) {
                if date == today { continue }
                // Deterministic per (day, task): ~80% done, ~10% skipped, ~10% missed.
                let seed = (Int(date.timeIntervalSince1970 / 86_400) + index * 7) % 10
                let status: CompletionStatus?
                switch seed {
                case 0:  status = nil        // missed — no completion logged
                case 1:  status = .skipped
                default: status = .done
                }
                if let status {
                    context.insert(Completion(scheduledDate: date, status: status, task: task))
                    completionCount += 1
                }
            }
        }

        if let error = save(context) {
            return .message("Save FAILED: \(error)")
        }
        return .message("Added \(tasks.count) tasks and \(completionCount) history entries. Check the Tasks tab.")
    }

    /// Deletes all tasks and their completions.
    @discardableResult
    static func wipe(_ context: ModelContext) -> Result {
        let before = (try? context.fetch(FetchDescriptor<TaskItem>()))?.count ?? 0
        try? context.delete(model: Completion.self)
        try? context.delete(model: TaskItem.self)
        if let error = save(context) {
            return .message("Delete FAILED: \(error)")
        }
        return .message("Deleted \(before) task(s) and their history.")
    }

    /// Saves; returns a description of any real failure, so it isn't confused with
    /// the benign "fopen failed for data file" cache log CoreData emits on its own.
    private static func save(_ context: ModelContext) -> String? {
        do {
            try context.save()
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
