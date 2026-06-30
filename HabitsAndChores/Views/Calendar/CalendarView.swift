import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(HouseholdsModel.self) private var households
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived })
    private var tasks: [TaskItem]
    @Query private var allTodos: [TodoItem]

    @State private var month: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                monthGrid
                Divider().padding(.horizontal)
                dayDetail
            }
            .padding(.vertical)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(orderedWeekdaySymbols(), id: \.self) { symbol in
                Text(symbol).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Grid

    private var monthGrid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    DayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDay),
                        isToday: calendar.isDateInToday(date),
                        scheduledCount: scheduledCount(on: date),
                        completedCount: completedCount(on: date)
                    )
                    .onTapGesture { selectedDay = date }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Day detail

    private var dayDetail: some View {
        let items = scheduledTasks(on: selectedDay)
        let shared = sharedChores(on: selectedDay)
        let dayTodos = todos(on: selectedDay)
        let daySharedTodos = sharedTodos(on: selectedDay)
        let isToday = calendar.isDateInToday(selectedDay)
        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedDay.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)
                .padding(.horizontal)
            if items.isEmpty && shared.isEmpty && dayTodos.isEmpty && daySharedTodos.isEmpty {
                Text("Nothing scheduled.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(items) { task in
                    TaskRow(task: task, day: selectedDay, toggle: { toggle(task, on: selectedDay) })
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                // A shared chore's `isDone` only reflects its *current* occurrence, so
                // it's only shown (and toggleable) as done on today; other cells show
                // it as scheduled-but-not-done to avoid a completed daily chore looking
                // done on every day.
                ForEach(shared, id: \.chore.id) { item in
                    SharedTaskRow(chore: displayChore(item.chore, on: selectedDay),
                                  householdName: item.household.name) {
                        guard isToday else { return }
                        households.setDone(item.chore, in: item.household, !item.chore.isDone)
                        Haptics.tap()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                // To-dos placed on their planned day (or due date). One-off, so done
                // state is a single value and the toggle is live on any day.
                ForEach(dayTodos) { todo in
                    CalendarTodoRow(title: todo.title, isDone: todo.isDone,
                                    dueDate: todo.dueDate, priority: todo.priority,
                                    subtitle: nil) { toggleTodo(todo) }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                ForEach(daySharedTodos, id: \.chore.id) { item in
                    CalendarTodoRow(title: item.chore.title, isDone: item.chore.isDone,
                                    dueDate: item.chore.dueDate, priority: item.chore.priority,
                                    subtitle: item.household.name) {
                        households.setDone(item.chore, in: item.household, !item.chore.isDone)
                        Haptics.tap()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func scheduledTasks(on day: Date) -> [TaskItem] {
        tasks.filter { SchedulingEngine.isScheduled($0, on: day) }
    }

    /// Total scheduled items on `day` across tasks, shared chores, and to-dos.
    private func scheduledCount(on day: Date) -> Int {
        scheduledTasks(on: day).count + sharedChores(on: day).count
            + todos(on: day).count + sharedTodos(on: day).count
    }

    /// Completed items on `day`. Shared-chore completion is only meaningful on today
    /// (per-occurrence); to-do completion is a single state, accurate on any day.
    private func completedCount(on day: Date) -> Int {
        let tasksDone = scheduledTasks(on: day).filter { $0.isCompleted(on: day) }.count
        let todosDone = todos(on: day).filter(\.isDone).count
        let sharedTodosDone = sharedTodos(on: day).filter { $0.chore.isDone }.count
        return tasksDone + sharedCompletedCount(on: day) + todosDone + sharedTodosDone
    }

    /// Shared household chores (the whole household, like the Tasks list) scheduled on
    /// `day`. The calendar is personal-only otherwise, so without this a user whose
    /// tasks live in a household sees an empty calendar.
    private func sharedChores(on day: Date) -> [(household: Household, chore: SharedChore)] {
        households.sharedTasks(isTodo: false, .all).filter {
            SchedulingEngine.isScheduled(frequency: $0.chore.frequency, anchor: $0.chore.createdAt, on: day)
        }
    }

    /// A shared chore's `isDone` only reflects its current occurrence, so it's only a
    /// meaningful "completed" signal on today; past/future cells show it as scheduled.
    private func sharedCompletedCount(on day: Date) -> Int {
        guard calendar.isDateInToday(day) else { return 0 }
        return sharedChores(on: day).filter { $0.chore.isDone }.count
    }

    /// Personal to-dos placed on `day` — their planned "do" day if set, otherwise
    /// their due date. To-dos are one-off, so their done-state is accurate on any day.
    private func todos(on day: Date) -> [TodoItem] {
        allTodos.filter { todo in
            guard let placed = todo.scheduledDate ?? todo.dueDate else { return false }
            return calendar.isDate(placed, inSameDayAs: day)
        }
    }

    /// Shared household to-dos placed on `day` (planned day, else due date).
    private func sharedTodos(on day: Date) -> [(household: Household, chore: SharedChore)] {
        households.sharedTasks(isTodo: true, .all).filter {
            guard let placed = $0.chore.scheduledDate ?? $0.chore.dueDate else { return false }
            return calendar.isDate(placed, inSameDayAs: day)
        }
    }

    private func toggleTodo(_ todo: TodoItem) {
        todo.toggle()
        Haptics.tap()
        Task { @MainActor in context.saveOrReport() }
        Task { await NotificationManager.shared.reschedule(todo: todo) }
    }

    /// The chore as it should display on `day`: its real done-state on today, but
    /// forced not-done on other days (we don't load shared per-occurrence history, so
    /// the current `isDone` would otherwise paint every day as completed).
    private func displayChore(_ chore: SharedChore, on day: Date) -> SharedChore {
        guard !calendar.isDateInToday(day) else { return chore }
        var copy = chore
        copy.isDone = false
        copy.completedByMembers = []
        return copy
    }

    private func toggle(_ task: TaskItem, on day: Date) {
        let wasDone = task.completion(on: day) != nil
        if let existing = task.completion(on: day) {
            context.delete(existing)
        } else {
            context.insert(Completion(scheduledDate: day, status: .done, task: task))
        }
        if !wasDone { Haptics.tap() }   // instant tactile feedback, before persisting
        // Persist off the tap's critical path so the row updates this frame instead
        // of waiting on the synchronous (CloudKit-mirrored) save.
        Task { @MainActor in context.saveOrReport() }
    }

    private func shiftMonth(_ delta: Int) {
        if let new = calendar.date(byAdding: .month, value: delta, to: month) {
            month = new
        }
    }

    /// Builds an array of 42 slots (6 weeks); `nil` for leading/trailing padding.
    private func monthDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let firstWeekday = calendar.dateComponents([.weekday], from: interval.start).weekday
        else { return [] }

        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        var slots: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<daysInMonth {
            slots.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while slots.count % 7 != 0 { slots.append(nil) }
        return slots
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

/// A compact to-do row for the calendar's day detail: completion toggle, title,
/// and a caption with an optional household name, the due date, and a priority flag.
private struct CalendarTodoRow: View {
    let title: String
    let isDone: Bool
    let dueDate: Date?
    let priority: TodoPriority
    let subtitle: String?
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let subtitle {
                        Label(subtitle, systemImage: "house.fill")
                    }
                    if priority != .none {
                        Image(systemName: "flag.fill").foregroundStyle(priority.color)
                    }
                    if let dueDate {
                        Label(dueDate.formatted(.dateTime.month().day()), systemImage: "calendar")
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

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let scheduledCount: Int
    let completedCount: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
            HStack(spacing: 2) {
                if scheduledCount > 0 {
                    Circle()
                        .fill(completedCount == scheduledCount ? Color.green : Color.accentColor)
                        .frame(width: 5, height: 5)
                    if scheduledCount > 1 {
                        Text("\(scheduledCount)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                } else {
                    Circle().fill(.clear).frame(width: 5, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack { CalendarView() }
        .modelContainer(PreviewData.container)
        .environment(HouseholdsModel())
}
