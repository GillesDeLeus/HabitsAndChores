import WidgetKit
import SwiftUI
import SwiftData

struct TodayEntry: TimelineEntry {
    let date: Date
    let total: Int
    let completed: Int
    let upcoming: [String]
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, total: 4, completed: 1, upcoming: ["Drink water", "Walk the dog"])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh at the next hour boundary.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Reads today's scheduled tasks directly from the shared SwiftData store.
    private func makeEntry() -> TodayEntry {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        do {
            let schema = Schema([TaskItem.self, Completion.self, TodoItem.self])
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            let all = try context.fetch(FetchDescriptor<TaskItem>())
            let due = all.filter { !$0.isArchived && SchedulingEngine.isScheduled($0, on: today) }
            let done = due.filter { $0.isCompleted(on: today) }.count
            let upcoming = due.filter { !$0.isCompleted(on: today) }.prefix(3).map(\.title)
            return TodayEntry(date: .now, total: due.count, completed: done, upcoming: Array(upcoming))
        } catch {
            return TodayEntry(date: .now, total: 0, completed: 0, upcoming: [])
        }
    }
}

struct TodayWidgetEntryView: View {
    var entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                Text("Today").font(.headline)
                Spacer()
                Text("\(entry.completed)/\(entry.total)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            Divider()
            if entry.upcoming.isEmpty {
                Text(entry.total == 0 ? "Nothing scheduled" : "All done! 🎉")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.upcoming, id: \.self) { title in
                    Label(title, systemImage: "circle")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your habits & chores due today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
