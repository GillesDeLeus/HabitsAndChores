import Foundation
import SwiftData

/// In-memory SwiftData container seeded with sample tasks for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: TaskItem.self, Completion.self, configurations: config)
        let context = container.mainContext

        let samples: [TaskItem] = [
            TaskItem(title: "Drink water", details: "Stay hydrated.", kind: .habit,
                     category: .health, frequency: .daily, symbolName: "drop.fill", colorHue: 0.55),
            TaskItem(title: "Take out the trash", kind: .chore, category: .home,
                     frequency: .weekly(on: [3, 6]), symbolName: "trash.fill", colorHue: 0.08),
            TaskItem(title: "Review budget", kind: .chore, category: .finance,
                     frequency: .monthly(day: 1), symbolName: "chart.pie.fill", colorHue: 0.13)
        ]
        for s in samples { context.insert(s) }

        // Mark the first one done today to exercise completed states.
        let done = Completion(scheduledDate: .now, status: .done, task: samples[0])
        context.insert(done)

        try? context.save()
        return container
    }()
}
