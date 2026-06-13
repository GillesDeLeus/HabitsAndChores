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

    @State private var filter: Filter = .open
    @State private var newTitle = ""

    // Newest first.
    @Query(sort: \TodoItem.createdAt, order: .reverse)
    private var todos: [TodoItem]

    private var filtered: [TodoItem] {
        switch filter {
        case .open: return todos.filter { !$0.isDone }
        case .done: return todos.filter { $0.isDone }
        case .all:  return todos.filter { !$0.isDone } + todos.filter { $0.isDone }
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

            Section {
                if filtered.isEmpty {
                    Text(emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { todo in
                        TodoRow(todo: todo) { toggle(todo) }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .open: return String(localized: "Nothing to do. Add something above.")
        case .done: return String(localized: "No completed to-dos yet.")
        case .all:  return String(localized: "No to-dos yet.")
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        context.insert(TodoItem(title: title))
        newTitle = ""
        try? context.save()
    }

    private func toggle(_ todo: TodoItem) {
        todo.toggle()
        try? context.save()
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(filtered[index]) }
        try? context.save()
    }
}

private struct TodoRow: View {
    let todo: TodoItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? Color.accentColor : .secondary)
                Text(todo.title)
                    .strikethrough(todo.isDone, color: .secondary)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { TodoListView() }
        .modelContainer(for: TodoItem.self, inMemory: true)
}
