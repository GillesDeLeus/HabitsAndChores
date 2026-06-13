import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.sortIndex) private var tasks: [TaskItem]

    enum SortMode: String, CaseIterable, Identifiable {
        case manual, title, category
        var id: String { rawValue }
        var label: String {
            switch self {
            case .manual:   return String(localized: "Manual order")
            case .title:    return String(localized: "Title (A–Z)")
            case .category: return String(localized: "By category")
            }
        }
    }

    @State private var showingAdd = false
    @State private var showingTemplates = false
    @State private var sortMode: SortMode = .manual
    @State private var search = ""

    private var active: [TaskItem] {
        let base = tasks.filter { !$0.isArchived }
        guard !search.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
    private var archived: [TaskItem] {
        let base = tasks.filter { $0.isArchived }
        guard !search.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if active.isEmpty && archived.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No tasks yet" : "No matches", systemImage: "checklist")
                } description: {
                    Text(search.isEmpty ? "Add your own or browse the built-in library." : "Try a different search.")
                } actions: {
                    if search.isEmpty {
                        Button("Browse library") { showingTemplates = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                activeContent
                if !archived.isEmpty {
                    Section(header: Text("Archived")) {
                        ForEach(archived) { task in
                            TaskInfoRow(task: task).foregroundStyle(.secondary)
                        }
                        .onDelete { delete(archived, at: $0) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search tasks")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingTemplates = true } label: { Image(systemName: "books.vertical.fill") }
                    .accessibilityLabel("Template library")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort and group")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add task")
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddEditTaskView(task: nil) }
        }
        .sheet(isPresented: $showingTemplates) {
            TemplateLibraryView()
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch sortMode {
        case .manual:
            Section(header: Text("Active")) {
                ForEach(active) { task in taskLink(task) }
                    .onMove(perform: search.isEmpty ? moveActive : nil)
                    .onDelete { archive(active, at: $0) }
            }
        case .title:
            Section(header: Text("Active")) {
                ForEach(active.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }) { task in
                    taskLink(task)
                }
            }
        case .category:
            ForEach(TaskCategory.allCases) { category in
                let items = active.filter { $0.category == category }
                if !items.isEmpty {
                    Section(header: Text(category.localizedName)) {
                        ForEach(items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }) { task in
                            taskLink(task)
                        }
                    }
                }
            }
        }
    }

    private func taskLink(_ task: TaskItem) -> some View {
        NavigationLink { AddEditTaskView(task: task) } label: { TaskInfoRow(task: task) }
    }

    private func moveActive(from source: IndexSet, to destination: Int) {
        var reordered = active
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, task) in reordered.enumerated() { task.sortIndex = index }
        context.saveOrReport()
    }

    private func archive(_ list: [TaskItem], at offsets: IndexSet) {
        for index in offsets {
            list[index].isArchived = true
            NotificationManager.shared.cancel(taskID: list[index].id)
        }
        context.saveOrReport()
    }

    private func delete(_ list: [TaskItem], at offsets: IndexSet) {
        for index in offsets {
            NotificationManager.shared.cancel(taskID: list[index].id)
            context.delete(list[index])
        }
        context.saveOrReport()
    }
}

private struct TaskInfoRow: View {
    let task: TaskItem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.symbolName)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(task.color, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                Text("\(task.kind.localizedName) · \(task.frequency.localizedDescription)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if task.hasReminder {
                Image(systemName: "bell.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack { TaskListView() }
        .modelContainer(PreviewData.container)
}
