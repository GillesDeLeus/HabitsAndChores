import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var context

    enum Filter: String, CaseIterable, Identifiable {
        case open, done, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: return String(localized: "Open")
            case .done: return String(localized: "Done")
            case .all:  return String(localized: "All")
            }
        }
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case manual, dueDate, priority
        var id: String { rawValue }
        var label: String {
            switch self {
            case .manual:   return String(localized: "Manual order")
            case .dueDate:  return String(localized: "Due date")
            case .priority: return String(localized: "Priority")
            }
        }
    }

    @Environment(HouseholdsModel.self) private var households

    @State private var filter: Filter = .open
    @State private var sortMode: SortMode = .manual
    @State private var newTitle = ""
    @State private var editing: TodoItem?
    @State private var creating = false
    @State private var sharedEditing: SharedTodoTarget?

    // Filters (nil = all).
    @State private var categoryFilter: TaskCategory?
    @State private var priorityFilter: TodoPriority?
    private var isFiltering: Bool { categoryFilter != nil || priorityFilter != nil }

    private func matches(_ todo: TodoItem) -> Bool {
        (categoryFilter == nil || todo.category == categoryFilter)
            && (priorityFilter == nil || todo.priority == priorityFilter)
    }
    private func matches(_ chore: SharedChore) -> Bool {
        (categoryFilter == nil || chore.category == categoryFilter)
            && (priorityFilter == nil || chore.priority == priorityFilter)
    }

    // Manual order: lowest sortIndex first.
    @Query(sort: \TodoItem.sortIndex, order: .forward)
    private var todos: [TodoItem]

    private var open: [TodoItem] { sorted(todos.filter { !$0.isDone && matches($0) }) }
    private var done: [TodoItem] { sorted(todos.filter { $0.isDone && matches($0) }) }

    /// Shared household to-dos, partitioned by done state (search/filter applied).
    private var sharedOpen: [SharedTodoTarget] {
        households.sharedTasks(isTodo: true).filter { !$0.chore.isDone && matches($0.chore) }
            .map { SharedTodoTarget(household: $0.household, chore: $0.chore) }
    }
    private var sharedDone: [SharedTodoTarget] {
        households.sharedTasks(isTodo: true).filter { $0.chore.isDone && matches($0.chore) }
            .map { SharedTodoTarget(household: $0.household, chore: $0.chore) }
    }

    private func sorted(_ list: [TodoItem]) -> [TodoItem] {
        switch sortMode {
        case .manual:
            return list   // already in sortIndex order from the query
        case .dueDate:
            return list.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case .priority:
            return list.sorted {
                $0.priorityRaw != $1.priorityRaw ? $0.priorityRaw > $1.priorityRaw : $0.sortIndex < $1.sortIndex
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    TextField("Add a to-do", text: $newTitle)
                        .onSubmit(add)
                        .submitLabel(.done)
                }
            }

            // Open (reorderable) unless we're showing only completed.
            if filter != .done {
                Section(open.isEmpty && sharedOpen.isEmpty ? "" : String(localized: "Open")) {
                    if open.isEmpty && sharedOpen.isEmpty {
                        if !households.hasLoadedHouseholds {
                            // Shared to-dos may still be loading.
                            HStack { Spacer(); ProgressView("Loading…"); Spacer() }
                                .listRowSeparator(.hidden)
                        } else {
                            Text("Nothing to do. Add something above.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(open) { todo in
                            TodoRow(todo: todo) { toggle(todo) } edit: { editing = todo }
                        }
                        .onMove(perform: (sortMode == .manual && !isFiltering) ? moveOpen : nil)
                        .onDelete { deleteRows(open, $0) }
                        ForEach(sharedOpen) { target in
                            SharedTodoRow(target: target) {
                                households.setDone(target.chore, in: target.household, !target.chore.isDone)
                            } edit: { sharedEditing = target }
                        }
                    }
                }
            }

            // Completed.
            if filter != .open {
                Section(done.isEmpty && sharedDone.isEmpty ? "" : String(localized: "Completed")) {
                    if done.isEmpty && sharedDone.isEmpty {
                        Text("No completed to-dos yet.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(done) { todo in
                            TodoRow(todo: todo) { toggle(todo) } edit: { editing = todo }
                        }
                        .onDelete { deleteRows(done, $0) }
                        ForEach(sharedDone) { target in
                            SharedTodoRow(target: target) {
                                households.setDone(target.chore, in: target.household, !target.chore.isDone)
                            } edit: { sharedEditing = target }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $categoryFilter) {
                        Text("All categories").tag(TaskCategory?.none)
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.localizedName, systemImage: cat.symbolName).tag(TaskCategory?.some(cat))
                        }
                    }
                    Picker("Priority", selection: $priorityFilter) {
                        Text("All priorities").tag(TodoPriority?.none)
                        ForEach(TodoPriority.allCases) { p in
                            Text(p.label).tag(TodoPriority?.some(p))
                        }
                    }
                    if isFiltering {
                        Section {
                            Button("Clear filters", systemImage: "xmark.circle", role: .destructive) {
                                categoryFilter = nil; priorityFilter = nil
                            }
                        }
                    }
                } label: {
                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter to-dos")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort to-dos")
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New to-do with details")
            }
        }
        .sheet(item: $editing) { TodoEditView(todo: $0) }
        .sheet(isPresented: $creating) { TodoEditView(subject: .todo(nil)) }
        .sheet(item: $sharedEditing) { target in
            TodoEditView(subject: .shared(target.household, target.chore))
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        // New items go to the top of the open list.
        let topIndex = (todos.map(\.sortIndex).min() ?? 0) - 1
        context.insert(TodoItem(title: title, sortIndex: topIndex))
        newTitle = ""
        context.saveOrReport()
    }

    private func toggle(_ todo: TodoItem) {
        todo.toggle()
        Haptics.tap()   // instant tactile feedback, before persisting
        // Persist off the tap's critical path so the row updates this frame instead
        // of waiting on the synchronous (CloudKit-mirrored) save.
        Task { @MainActor in context.saveOrReport() }
        Task { await NotificationManager.shared.reschedule(todo: todo) }   // clears reminder when done
    }

    private func moveOpen(from source: IndexSet, to destination: Int) {
        var reordered = open
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, todo) in reordered.enumerated() { todo.sortIndex = index }
        context.saveOrReport()
    }

    private func deleteRows(_ list: [TodoItem], _ offsets: IndexSet) {
        for index in offsets {
            NotificationManager.shared.cancelTodo(id: list[index].id)
            context.delete(list[index])
        }
        context.saveOrReport()
    }
}

private struct TodoRow: View {
    let todo: TodoItem
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark not done" : "Mark done")

            Button(action: edit) {
                HStack(spacing: 8) {
                    if todo.priority != .none {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(todo.priority.color)
                            .accessibilityLabel("\(todo.priority.label) priority")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(todo.title)
                            .strikethrough(todo.isDone, color: .secondary)
                            .foregroundStyle(todo.isDone ? .secondary : .primary)
                        HStack(spacing: 8) {
                            if let due = todo.dueDate {
                                Label(due.formatted(.dateTime.month().day()), systemImage: "calendar")
                                    .foregroundStyle(todo.isOverdue ? .red : .secondary)
                            }
                            if let scheduled = todo.scheduledDate {
                                Label(scheduled.formatted(.dateTime.month().day()), systemImage: "calendar.badge.clock")
                            }
                            if let reminder = todo.reminderSummary {
                                Label(reminder, systemImage: "bell.fill")
                            }
                            if let category = todo.category {
                                Label(category.localizedName, systemImage: category.symbolName)
                            }
                            if !todo.details.isEmpty {
                                Image(systemName: "text.alignleft")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A shared household to-do paired with its household, for the to-do list.
struct SharedTodoTarget: Identifiable {
    let household: Household
    let chore: SharedChore
    var id: String { chore.id }
}

private struct SharedTodoRow: View {
    let target: SharedTodoTarget
    let toggle: () -> Void
    let edit: () -> Void

    private var chore: SharedChore { target.chore }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: chore.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chore.isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chore.isDone ? "Mark not done" : "Mark done")

            Button(action: edit) {
                HStack(spacing: 8) {
                    if chore.priority != .none {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(chore.priority.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chore.title)
                            .strikethrough(chore.isDone, color: .secondary)
                            .foregroundStyle(chore.isDone ? .secondary : .primary)
                        HStack(spacing: 8) {
                            Label(target.household.name, systemImage: "house.fill")
                            if let due = chore.dueDate {
                                Label(due.formatted(.dateTime.month().day()), systemImage: "calendar")
                            }
                            if let scheduled = chore.scheduledDate {
                                Label(scheduled.formatted(.dateTime.month().day()), systemImage: "calendar.badge.clock")
                            }
                            if chore.hasMultipleAssignees {
                                Text("· \(chore.progressSummary)")
                            } else if let summary = chore.assigneeSummary() {
                                Text("· \(summary)")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack { TodoListView() }
        .modelContainer(for: TodoItem.self, inMemory: true)
        .environment(HouseholdsModel())
}
