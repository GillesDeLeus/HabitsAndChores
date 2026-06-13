import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }, sort: \TaskItem.title)
    private var tasks: [TaskItem]

    @State private var confettiTrigger = 0
    @State private var summary = GamificationEngine.Summary()

    private let today = Calendar.current.startOfDay(for: .now)

    private var dueToday: [TaskItem] {
        tasks.filter { SchedulingEngine.isScheduled($0, on: today) }
    }

    private var completedCount: Int {
        dueToday.filter { $0.isCompleted(on: today) }.count
    }

    /// Cheap key that changes whenever a task or completion is added/removed, used
    /// to recompute the (relatively expensive) gamification summary only when needed.
    private var statsKey: String {
        "\(tasks.count)-\(tasks.reduce(0) { $0 + $1.completions.count })"
    }

    var body: some View {
        NavigationStack {
            Group {
                if dueToday.isEmpty {
                    ContentUnavailableView(
                        "Nothing scheduled today",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Enjoy the day off, or add a task from the library.")
                    )
                } else {
                    List {
                        Section {
                            ProgressHeader(completed: completedCount, total: dueToday.count, summary: summary)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        Section(header: Text("Due today")) {
                            ForEach(dueToday) { task in
                                TaskRow(task: task, day: today, toggle: { toggle(task) })
                            }
                        }
                    }
                }
            }
            .navigationTitle(today.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .overlay { ConfettiView(trigger: confettiTrigger) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CalendarView() } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Calendar")
                }
            }
            .task(id: statsKey) { summary = GamificationEngine.summary(for: tasks) }
        }
    }

    private func toggle(_ task: TaskItem) {
        let wasDone = task.completion(on: today) != nil
        if let existing = task.completion(on: today) {
            context.delete(existing)
        } else {
            let c = Completion(scheduledDate: today, status: .done, task: task)
            context.insert(c)
        }
        context.saveOrReport()

        // Celebrate only when marking done (not when un-checking), and only if it
        // unlocked something new (a badge or a level-up).
        if !wasDone {
            Haptics.tap()
            if AchievementTracker.registerAndCheck(GamificationEngine.summary(for: tasks)) {
                Haptics.celebrate()
                confettiTrigger += 1
            }
        }
    }
}

private struct ProgressHeader: View {
    let completed: Int
    let total: Int
    let summary: GamificationEngine.Summary
    private var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
                VStack {
                    Text("\(completed)/\(total)").font(.title2).bold()
                    Text("today").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            HStack(spacing: 10) {
                // Level + points chip.
                HStack(spacing: 6) {
                    Image(systemName: "star.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Level \(summary.level)").font(.subheadline.bold())
                        Text("\(summary.totalPoints) pts").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))

                // Weekly goal chip.
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(summary.weeklyProgress * 100))% week").font(.subheadline.bold())
                        Text("\(summary.completedThisWeek)/\(summary.scheduledThisWeek) done")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview {
    TodayView()
        .modelContainer(PreviewData.container)
}
