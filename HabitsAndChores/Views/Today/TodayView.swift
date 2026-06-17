import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(HouseholdsModel.self) private var households
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }, sort: \TaskItem.title)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TodoItem> { !$0.isDone })
    private var openTodos: [TodoItem]

    @State private var confettiTrigger = 0
    @State private var summary = GamificationEngine.Summary()

    /// "Today" is refreshed when the calendar day rolls over (even while the app
    /// stays foregrounded) and when it returns to the foreground, so the list
    /// doesn't get stuck showing yesterday in a long-lived session.
    @State private var today = Calendar.current.startOfDay(for: .now)

    /// Day-scheduled tasks due today, plus floating ("once a week/month") tasks that
    /// are outstanding for their current period (or were completed today, so the row
    /// lingers, struck through and undoable, until the day rolls over).
    private var dueToday: [TaskItem] {
        tasks.filter { SchedulingEngine.belongsInToday($0, on: today) }
    }

    /// The day a given task's completion is keyed to today (its own day for
    /// day-scheduled tasks, the period start for floating ones).
    private func occurrenceDay(for task: TaskItem) -> Date {
        SchedulingEngine.occurrenceDate(for: task, on: today) ?? today
    }

    /// Shared household chores relevant to me (assigned to me, or unassigned/up-for-
    /// grabs) and scheduled for today. Chores assigned to *other* members aren't
    /// shown here (they still appear in the Tasks list and the household screen).
    private var sharedDueToday: [(household: Household, chore: SharedChore)] {
        households.sharedTasks(isTodo: false, .mineOrUnassigned).filter {
            SchedulingEngine.isScheduled(frequency: $0.chore.frequency, anchor: $0.chore.createdAt, on: today)
        }
    }

    /// Open to-dos scheduled for today or earlier — they surface in Today until done.
    private var scheduledTodos: [TodoItem] {
        openTodos.filter { $0.isScheduled(onOrBefore: today) }
            .sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
    }

    /// Shared household to-dos (mine or unassigned) scheduled for today or earlier.
    private var scheduledSharedTodos: [(household: Household, chore: SharedChore)] {
        households.sharedTasks(isTodo: true, .mineOrUnassigned)
            .filter { $0.chore.isScheduledTodo(onOrBefore: today) }
            .sorted { ($0.chore.scheduledDate ?? .distantPast) < ($1.chore.scheduledDate ?? .distantPast) }
    }

    private var hasTodos: Bool { !scheduledTodos.isEmpty || !scheduledSharedTodos.isEmpty }

    /// Today's count includes shared tasks; gamification/streaks stay local-only.
    private var completedCount: Int {
        dueToday.filter { $0.isCompleted(on: occurrenceDay(for: $0)) }.count
            + sharedDueToday.filter { $0.chore.isDone }.count
    }
    private var totalCount: Int { dueToday.count + sharedDueToday.count }

    /// Cheap key that changes whenever a task or completion is added/removed — or a
    /// completion flips done↔skipped at equal count — used to recompute the
    /// (relatively expensive) gamification summary only when needed.
    private var statsKey: String {
        var total = 0, done = 0
        for task in tasks {
            for c in (task.completions ?? []) {
                total += 1
                if c.status == .done { done += 1 }
            }
        }
        return "\(tasks.count)-\(total)-\(done)-\(today.timeIntervalSinceReferenceDate)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if totalCount == 0 && !hasTodos {
                    ContentUnavailableView(
                        "Nothing scheduled today",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Enjoy the day off, or add a task from the library.")
                    )
                } else {
                    List {
                        if totalCount > 0 {
                            Section {
                                ProgressHeader(completed: completedCount, total: totalCount, summary: summary)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            }
                            Section(header: Text("Due today")) {
                                ForEach(dueToday) { task in
                                    let day = occurrenceDay(for: task)
                                    TaskRow(task: task, day: day, toggle: { toggle(task, on: day) })
                                }
                                ForEach(sharedDueToday, id: \.chore.id) { item in
                                    SharedTaskRow(chore: item.chore, householdName: item.household.name) {
                                        households.setDone(item.chore, in: item.household, !item.chore.isDone)
                                        Haptics.tap()
                                    }
                                }
                            }
                        }
                        if hasTodos {
                            Section(header: Text("To-dos")) {
                                ForEach(scheduledTodos) { todo in
                                    TodayTodoRow(todo: todo) { toggleTodo(todo) }
                                }
                                ForEach(scheduledSharedTodos, id: \.chore.id) { item in
                                    TodaySharedTodoRow(chore: item.chore, householdName: item.household.name) {
                                        households.setDone(item.chore, in: item.household, true)
                                        Haptics.tap()
                                    }
                                }
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
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                today = Calendar.current.startOfDay(for: .now)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Calendar.current.startOfDay(for: .now) }
            }
        }
    }

    private func toggleTodo(_ todo: TodoItem) {
        todo.toggle()
        Haptics.tap()   // instant tactile feedback, before persisting
        // Persist off the tap's critical path so the row updates this frame instead
        // of waiting on the synchronous (CloudKit-mirrored) save.
        Task { @MainActor in context.saveOrReport() }
        Task { await NotificationManager.shared.reschedule(todo: todo) }
    }

    private func toggle(_ task: TaskItem, on day: Date) {
        let wasDone = task.completion(on: day) != nil
        if let existing = task.completion(on: day) {
            context.delete(existing)
        } else {
            context.insert(Completion(scheduledDate: day, status: .done, task: task))
        }
        if !wasDone { Haptics.tap() }   // instant tactile feedback, before persisting

        // Persist and recompute gamification off the tap's critical path so the row
        // and haptic land immediately rather than waiting on the synchronous save.
        // Celebrate only when marking done, and only if it unlocked something new.
        Task { @MainActor in
            context.saveOrReport()
            if !wasDone, AchievementTracker.registerAndCheck(GamificationEngine.summary(for: tasks)) {
                Haptics.celebrate()
                confettiTrigger += 1
            }
        }
    }
}

private struct TodayTodoRow: View {
    let todo: TodoItem
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark done")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                HStack(spacing: 8) {
                    if todo.priority != .none {
                        Image(systemName: "flag.fill").foregroundStyle(todo.priority.color)
                    }
                    if let due = todo.dueDate {
                        Label(due.formatted(.dateTime.month().day()), systemImage: "calendar")
                            .foregroundStyle(todo.isOverdue ? .red : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

private struct TodaySharedTodoRow: View {
    let chore: SharedChore
    let householdName: String
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark done")

            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                    if let assignee = chore.assignee {
                        Text("\(householdName) · \(assignee)")
                    } else {
                        Text(householdName)
                    }
                    if let due = chore.dueDate {
                        Text("· due \(due.formatted(.dateTime.month().day()))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
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
        .environment(HouseholdsModel())
}
