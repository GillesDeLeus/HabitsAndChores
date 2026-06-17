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

    /// The real current day, refreshed when the calendar day rolls over (even while
    /// the app stays foregrounded) and on return to the foreground, so gamification
    /// and the "Today" anchor don't get stuck on yesterday.
    @State private var today = Calendar.current.startOfDay(for: .now)
    /// The day currently being viewed. Defaults to today; the header chevrons and a
    /// horizontal swipe move it so you can look ahead at what's planned (or back).
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current
    private var isViewingToday: Bool { calendar.isDate(selectedDay, inSameDayAs: today) }

    /// Day-scheduled tasks for the selected day, plus floating ("once a week/month")
    /// tasks outstanding for that day's period (the linger-after-completion rule only
    /// applies on the day you complete it).
    private var dueTasks: [TaskItem] {
        tasks.filter { SchedulingEngine.belongsInToday($0, on: selectedDay) }
    }

    /// The day a task's completion is keyed to for the selected day (its own day for
    /// day-scheduled tasks, the period start for floating ones).
    private func occurrenceDay(for task: TaskItem) -> Date {
        SchedulingEngine.occurrenceDate(for: task, on: selectedDay) ?? selectedDay
    }

    /// Shared household chores relevant to me (assigned to me, or unassigned/up-for-
    /// grabs) and scheduled on the selected day. Chores assigned to *other* members
    /// aren't shown here (they appear in the Tasks list and the household screen).
    private var sharedDueTasks: [(household: Household, chore: SharedChore)] {
        households.sharedTasks(isTodo: false, .mineOrUnassigned).filter {
            SchedulingEngine.isScheduled(frequency: $0.chore.frequency, anchor: $0.chore.createdAt, on: selectedDay)
        }
    }

    /// Open to-dos for the selected day. On today this includes anything scheduled
    /// on/before today (so overdue items surface); on other days it's exactly that
    /// day's planned to-dos.
    private var dueTodos: [TodoItem] {
        openTodos.filter { todoMatches(scheduled: $0.scheduledDate) }
            .sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
    }

    /// Shared household to-dos (mine or unassigned) for the selected day.
    private var sharedTodos: [(household: Household, chore: SharedChore)] {
        households.sharedTasks(isTodo: true, .mineOrUnassigned)
            .filter { !$0.chore.isDone && todoMatches(scheduled: $0.chore.scheduledDate) }
            .sorted { ($0.chore.scheduledDate ?? .distantPast) < ($1.chore.scheduledDate ?? .distantPast) }
    }

    /// Whether a to-do with the given planned date belongs on the selected day:
    /// on/before today when viewing today, else exactly the selected day.
    private func todoMatches(scheduled: Date?) -> Bool {
        guard let scheduled else { return false }
        let day = calendar.startOfDay(for: scheduled)
        return isViewingToday ? day <= selectedDay : calendar.isDate(day, inSameDayAs: selectedDay)
    }

    private var hasTodos: Bool { !dueTodos.isEmpty || !sharedTodos.isEmpty }

    /// Completed count for the selected day's ring. A shared chore's done-state is
    /// only meaningful for today (per-occurrence), so it's only counted there.
    private var completedCount: Int {
        dueTasks.filter { $0.isCompleted(on: occurrenceDay(for: $0)) }.count
            + (isViewingToday ? sharedDueTasks.filter { $0.chore.isDone }.count : 0)
    }
    private var totalCount: Int { dueTasks.count + sharedDueTasks.count }

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
            VStack(spacing: 0) {
                dayNavBar
                content
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { ConfettiView(trigger: confettiTrigger) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isViewingToday {
                        Button("Today") { withAnimation(.snappy) { selectedDay = today } }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CalendarView() } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Calendar")
                }
            }
            .task(id: statsKey) { summary = GamificationEngine.summary(for: tasks) }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshToday()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshToday() }
            }
        }
    }

    /// Header letting the user move between days (chevrons + a horizontal swipe on
    /// the list). Shows "Today / Tomorrow / Yesterday" near the present, else the
    /// weekday, with the full date beneath.
    private var dayNavBar: some View {
        HStack {
            Button { changeDay(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 36)
            }
            .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 1) {
                Text(relativeDayName).font(.headline)
                Text(selectedDay.formatted(.dateTime.month().day().year()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { changeDay(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 36)
            }
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var relativeDayName: String {
        if isViewingToday { return String(localized: "Today") }
        if let t = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(selectedDay, inSameDayAs: t) {
            return String(localized: "Tomorrow")
        }
        if let y = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(selectedDay, inSameDayAs: y) {
            return String(localized: "Yesterday")
        }
        return selectedDay.formatted(.dateTime.weekday(.wide))
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if totalCount == 0 && !hasTodos {
                ContentUnavailableView(
                    isViewingToday ? "Nothing scheduled today" : "Nothing scheduled",
                    systemImage: "checkmark.seal.fill",
                    description: Text(isViewingToday
                        ? "Enjoy the day off, or add a task from the library."
                        : "Nothing planned for this day yet.")
                )
            } else {
                List {
                    // The gamification ring is a today-only summary.
                    if isViewingToday && totalCount > 0 {
                        Section {
                            ProgressHeader(completed: completedCount, total: totalCount, summary: summary)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }
                    if totalCount > 0 {
                        Section(header: Text(isViewingToday ? "Due today" : "Scheduled")) {
                            ForEach(dueTasks) { task in
                                let day = occurrenceDay(for: task)
                                TaskRow(task: task, day: day, toggle: { toggle(task, on: day) })
                            }
                            // Shared completion is per current occurrence, so it's live
                            // on today and read-only (shown not-done) on other days.
                            ForEach(sharedDueTasks, id: \.chore.id) { item in
                                SharedTaskRow(chore: displayChore(item.chore), householdName: item.household.name) {
                                    guard isViewingToday else { return }
                                    households.setDone(item.chore, in: item.household, !item.chore.isDone)
                                    Haptics.tap()
                                }
                            }
                        }
                    }
                    if hasTodos {
                        Section(header: Text("To-dos")) {
                            ForEach(dueTodos) { todo in
                                TodayTodoRow(todo: todo) { toggleTodo(todo) }
                            }
                            ForEach(sharedTodos, id: \.chore.id) { item in
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Horizontal swipe to change day; runs alongside the List's vertical scroll
        // and only fires when the gesture is clearly horizontal, so it doesn't hijack
        // scrolling or row taps.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4,
                          abs(value.translation.width) > 56 else { return }
                    changeDay(value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private func changeDay(_ delta: Int) {
        if let d = calendar.date(byAdding: .day, value: delta, to: selectedDay) {
            withAnimation(.snappy) { selectedDay = calendar.startOfDay(for: d) }
        }
    }

    /// Refresh the real "today"; keep following it if we were already viewing today
    /// (so a day rollover / returning to the app lands on the new day), otherwise
    /// leave the user on whatever day they navigated to.
    private func refreshToday() {
        let wasToday = isViewingToday
        today = calendar.startOfDay(for: .now)
        if wasToday { selectedDay = today }
    }

    /// A shared chore as it should display on the selected day: its real done-state
    /// on today, forced not-done on other days (its `isDone` only reflects the current
    /// occurrence, so it would otherwise look done on every day).
    private func displayChore(_ chore: SharedChore) -> SharedChore {
        guard !isViewingToday else { return chore }
        var copy = chore
        copy.isDone = false
        copy.completedBy = nil
        return copy
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
