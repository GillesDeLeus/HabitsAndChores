import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }, sort: \TaskItem.title)
    private var tasks: [TaskItem]

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weeklyChart
                } header: {
                    Text("Last 7 days")
                }

                Section(header: Text("Per task")) {
                    ForEach(tasks) { task in
                        HStack {
                            Image(systemName: task.symbolName)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(task.color, in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading) {
                                Text(task.title)
                                Text("\(Int(completionRate(task) * 100))% over 30 days")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let streak = SchedulingEngine.currentStreak(for: task)
                            if streak > 0 {
                                Label("\(streak)", systemImage: "flame.fill")
                                    .font(.caption.bold()).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .overlay {
                if tasks.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "chart.bar",
                                           description: Text("Complete some tasks to see your progress."))
                }
            }
        }
    }

    private var weeklyChart: some View {
        let data = last7Days()
        return Chart(data, id: \.date) { item in
            BarMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Completed", item.completed)
            )
            .foregroundStyle(Color.accentColor)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .frame(height: 160)
        .padding(.vertical, 4)
    }

    // MARK: - Aggregation

    private func last7Days() -> [(date: Date, completed: Int)] {
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = tasks.filter { $0.isCompleted(on: day) }.count
            return (day, count)
        }
    }

    private func completionRate(_ task: TaskItem) -> Double {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -30, to: today) else { return 0 }
        let scheduled = SchedulingEngine.occurrences(for: task, in: DateInterval(start: start, end: today))
        guard !scheduled.isEmpty else { return 0 }
        let done = scheduled.filter { task.isCompleted(on: $0) }.count
        return Double(done) / Double(scheduled.count)
    }
}

#Preview {
    StatsView()
        .modelContainer(PreviewData.container)
}
