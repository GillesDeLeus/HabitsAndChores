import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(HouseholdsModel.self) private var households
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

    // Filters (nil = all).
    @State private var typeFilter: TaskKind?
    @State private var categoryFilter: TaskCategory?
    private var isFiltering: Bool { typeFilter != nil || categoryFilter != nil }

    private func matches(_ task: TaskItem) -> Bool {
        (search.isEmpty || task.title.localizedCaseInsensitiveContains(search))
            && (typeFilter == nil || task.kind == typeFilter)
            && (categoryFilter == nil || task.category == categoryFilter)
    }

    private var active: [TaskItem] { tasks.filter { !$0.isArchived && matches($0) } }
    private var archived: [TaskItem] { tasks.filter { $0.isArchived && matches($0) } }
    /// Shared household chores (recurring), matching the search + filters.
    private var sharedChores: [(household: Household, chore: SharedChore)] {
        households.sharedTasks(isTodo: false).filter { item in
            (search.isEmpty || item.chore.title.localizedCaseInsensitiveContains(search))
                && (typeFilter == nil || item.chore.kind == typeFilter)
                && (categoryFilter == nil || item.chore.category == categoryFilter)
        }
    }

    var body: some View {
        List {
            if active.isEmpty && archived.isEmpty && sharedChores.isEmpty {
                let narrowed = !search.isEmpty || isFiltering
                ContentUnavailableView {
                    Label(narrowed ? "No matches" : "No tasks yet", systemImage: "checklist")
                } description: {
                    Text(narrowed ? "Try a different search or filter." : "Add your own or browse the built-in library.")
                } actions: {
                    if !narrowed {
                        Button("Browse library") { showingTemplates = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                activeContent
                if !sharedChores.isEmpty {
                    Section(header: Text("Shared")) {
                        ForEach(sharedChores, id: \.chore.id) { item in
                            NavigationLink {
                                AddEditTaskView(shared: item.chore, in: item.household)
                            } label: {
                                SharedTaskInfoRow(chore: item.chore, householdName: item.household.name)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { sharedChores[$0] }.forEach { households.delete($0.chore, in: $0.household) }
                        }
                    }
                }
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
                    Picker("Type", selection: $typeFilter) {
                        Text("All types").tag(TaskKind?.none)
                        ForEach(TaskKind.allCases) { Text($0.localizedName).tag(TaskKind?.some($0)) }
                    }
                    Picker("Category", selection: $categoryFilter) {
                        Text("All categories").tag(TaskCategory?.none)
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.localizedName, systemImage: cat.symbolName).tag(TaskCategory?.some(cat))
                        }
                    }
                    if isFiltering {
                        Section {
                            Button("Clear filters", systemImage: "xmark.circle", role: .destructive) {
                                typeFilter = nil; categoryFilter = nil
                            }
                        }
                    }
                } label: {
                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
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
                    .onMove(perform: (search.isEmpty && !isFiltering) ? moveActive : nil)
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
        // Persist off the swipe's critical path so the row-removal animation stays
        // smooth instead of waiting on the synchronous (CloudKit-mirrored) save.
        Task { @MainActor in context.saveOrReport() }
    }

    private func delete(_ list: [TaskItem], at offsets: IndexSet) {
        for index in offsets {
            NotificationManager.shared.cancel(taskID: list[index].id)
            context.delete(list[index])
        }
        Task { @MainActor in context.saveOrReport() }
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

private struct SharedTaskInfoRow: View {
    let chore: SharedChore
    let householdName: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chore.symbolName)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(hue: chore.colorHue, saturation: 0.65, brightness: 0.9),
                            in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                    if let assignee = chore.assignee {
                        Text("\(householdName) · \(chore.frequency.localizedDescription) · \(assignee)")
                    } else {
                        Text("\(householdName) · \(chore.frequency.localizedDescription)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    NavigationStack { TaskListView() }
        .modelContainer(PreviewData.container)
        .environment(HouseholdsModel())
}
