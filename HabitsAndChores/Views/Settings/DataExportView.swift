import SwiftUI
import SwiftData

/// Exports the user's data (tasks, completions, to-dos, and account info) to a
/// JSON file the user can save or share — a GDPR-style data export.
struct DataExportView: View {
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \TodoItem.createdAt) private var todos: [TodoItem]
    @Environment(SocialAccount.self) private var account

    @State private var fileURL: URL?
    @State private var failed = false

    var body: some View {
        List {
            Section {
                Text("Download a copy of your data: your tasks and their completion history, your to-dos, and (if you have one) your public account details. The file is JSON and is created on your device.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Included") {
                LabeledContent("Tasks", value: "\(tasks.count)")
                LabeledContent("To-dos", value: "\(todos.count)")
                LabeledContent("Account", value: account.isJoined ? "@\(account.handle ?? "")" : "None")
            }

            Section {
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                } else if failed {
                    Text("Couldn't prepare the export.").foregroundStyle(.secondary)
                } else {
                    HStack { ProgressView(); Text("Preparing…").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Export data")
        .navigationBarTitleDisplayMode(.inline)
        .task { prepare() }
    }

    private func prepare() {
        let export = DataExport(
            exportedAt: .now,
            account: account.isJoined
                ? .init(handle: account.handle ?? "", displayName: account.displayName) : nil,
            tasks: tasks.map(DataExport.TaskRecord.init),
            todos: todos.map(DataExport.TodoRecord.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else { failed = true; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HabitsAndChores-Export.json")
        do {
            try data.write(to: url, options: .atomic)
            fileURL = url
        } catch {
            failed = true
        }
    }
}

/// Plain Codable mirror of the user's data for export.
private struct DataExport: Codable {
    let exportedAt: Date
    let account: Account?
    let tasks: [TaskRecord]
    let todos: [TodoRecord]

    struct Account: Codable {
        let handle: String
        let displayName: String
    }

    struct TaskRecord: Codable {
        let title: String
        let details: String
        let kind: String
        let category: String
        let frequency: FrequencyRule
        let startDate: Date
        let reminderHour: Int?
        let reminderMinute: Int?
        let isArchived: Bool
        let createdAt: Date
        let completions: [Completion]

        struct Completion: Codable { let date: Date; let status: String }

        init(_ task: TaskItem) {
            title = task.title
            details = task.details
            kind = task.kind.rawValue
            category = task.category.rawValue
            frequency = task.frequency
            startDate = task.startDate
            reminderHour = task.reminderHour
            reminderMinute = task.reminderMinute
            isArchived = task.isArchived
            createdAt = task.createdAt
            completions = (task.completions ?? [])
                .sorted { $0.scheduledDate < $1.scheduledDate }
                .map { Completion(date: $0.scheduledDate, status: $0.status.rawValue) }
        }
    }

    struct TodoRecord: Codable {
        let title: String
        let details: String
        let isDone: Bool
        let createdAt: Date
        let completedAt: Date?
        let dueDate: Date?
        let reminderDate: Date?
        let priority: String
        let category: String?

        init(_ todo: TodoItem) {
            title = todo.title
            details = todo.details
            isDone = todo.isDone
            createdAt = todo.createdAt
            completedAt = todo.completedAt
            dueDate = todo.dueDate
            reminderDate = todo.reminderDate
            priority = todo.priority.label
            category = todo.category?.localizedName
        }
    }
}
