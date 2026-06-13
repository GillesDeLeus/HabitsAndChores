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

    @State private var filter: Filter = .open
    @State private var sortMode: SortMode = .manual
    @State private var newTitle = ""
    @State private var editing: TodoItem?

    // Manual order: lowest sortIndex first.
    @Query(sort: \TodoItem.sortIndex, order: .forward)
    private var todos: [TodoItem]

    private var open: [TodoItem] { sorted(todos.filter { !$0.isDone }) }
    private var done: [TodoItem] { sorted(todos.filter { $0.isDone }) }

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
                Section(open.isEmpty ? "" : String(localized: "Open")) {
                    if open.isEmpty {
                        Text("Nothing to do. Add something above.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(open) { todo in
                            TodoRow(todo: todo) { toggle(todo) } edit: { editing = todo }
                        }
                        .onMove(perform: sortMode == .manual ? moveOpen : nil)
                        .onDelete { deleteRows(open, $0) }
                    }
                }
            }

            // Completed.
            if filter != .open {
                Section(done.isEmpty ? "" : String(localized: "Completed")) {
                    if done.isEmpty {
                        Text("No completed to-dos yet.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(done) { todo in
                            TodoRow(todo: todo) { toggle(todo) } edit: { editing = todo }
                        }
                        .onDelete { deleteRows(done, $0) }
                    }
                }
            }
        }
        .toolbar {
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
        }
        .sheet(item: $editing) { TodoEditView(todo: $0) }
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
        context.saveOrReport()
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

#Preview {
    NavigationStack { TodoListView() }
        .modelContainer(for: TodoItem.self, inMemory: true)
}
