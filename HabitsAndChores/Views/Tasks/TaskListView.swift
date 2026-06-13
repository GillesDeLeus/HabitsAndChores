import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.title) private var tasks: [TaskItem]

    @State private var showingAdd = false
    @State private var showingTemplates = false

    private var active: [TaskItem] { tasks.filter { !$0.isArchived } }
    private var archived: [TaskItem] { tasks.filter { $0.isArchived } }

    var body: some View {
        List {
            if active.isEmpty {
                ContentUnavailableView {
                    Label("No tasks yet", systemImage: "checklist")
                } description: {
                    Text("Add your own or browse the built-in library.")
                } actions: {
                    Button("Browse library") { showingTemplates = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section(header: Text("Active")) {
                    ForEach(active) { task in
                        NavigationLink {
                            AddEditTaskView(task: task)
                        } label: {
                            TaskInfoRow(task: task)
                        }
                    }
                    .onDelete { archive(active, at: $0) }
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingTemplates = true } label: { Image(systemName: "books.vertical.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddEditTaskView(task: nil) }
        }
        .sheet(isPresented: $showingTemplates) {
            TemplateLibraryView()
        }
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
