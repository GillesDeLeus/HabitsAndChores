import SwiftUI
import SwiftData

/// Edit a to-do's title, due date, reminder, and priority.
struct TodoEditView: View {
    let todo: TodoItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var reminderMode: TodoReminderMode
    @State private var reminderAt: Date
    @State private var reminderOffset: Double
    @State private var dailyTime: Date
    @State private var priority: TodoPriority
    @State private var category: TaskCategory?

    init(todo: TodoItem) {
        self.todo = todo
        let tomorrow9 = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
                                              of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now
        _title = State(initialValue: todo.title)
        _details = State(initialValue: todo.details)
        _hasDue = State(initialValue: todo.dueDate != nil)
        _due = State(initialValue: todo.dueDate ?? tomorrow9)
        _reminderMode = State(initialValue: todo.reminderMode)
        _reminderAt = State(initialValue: todo.reminderDate ?? tomorrow9)
        _reminderOffset = State(initialValue: todo.reminderOffset)
        _dailyTime = State(initialValue: todo.reminderDate ?? tomorrow9)
        _priority = State(initialValue: todo.priority)
        _category = State(initialValue: todo.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes (optional)", text: $details, axis: .vertical).lineLimit(1...4)
                }

                Section {
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section {
                    Picker("Reminder", selection: $reminderMode.animation()) {
                        ForEach(TodoReminderMode.allCases) { Text($0.label).tag($0) }
                    }
                    reminderDetail
                } footer: {
                    reminderFooter
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(TodoPriority.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    Picker("Category", selection: $category) {
                        Text("None").tag(TaskCategory?.none)
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.localizedName, systemImage: cat.symbolName).tag(TaskCategory?.some(cat))
                        }
                    }
                }
            }
            .navigationTitle("Edit To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: hasDue) { _, on in
                if !on, reminderMode == .beforeDue { reminderMode = .none }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var reminderDetail: some View {
        switch reminderMode {
        case .none:
            EmptyView()
        case .atTime:
            DatePicker("Time", selection: $reminderAt)
        case .beforeDue:
            if hasDue {
                Picker("When", selection: $reminderOffset) {
                    ForEach(TodoReminderOffset.options, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
            } else {
                Text("Turn on a due date to use this.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .dailyUntilDone:
            DatePicker("Time", selection: $dailyTime, displayedComponents: .hourAndMinute)
        }
    }

    @ViewBuilder
    private var reminderFooter: some View {
        switch reminderMode {
        case .none:           EmptyView()
        case .atTime:         Text("You'll get one notification at this time.")
        case .beforeDue:      Text("Reminds you relative to the due date.")
        case .dailyUntilDone: Text("Reminds you every day at this time until you mark it done.")
        }
    }

    private func save() {
        todo.title = title.trimmingCharacters(in: .whitespaces)
        todo.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.dueDate = hasDue ? due : nil
        // "Before due" needs a due date.
        todo.reminderMode = (reminderMode == .beforeDue && !hasDue) ? .none : reminderMode
        switch todo.reminderMode {
        case .none:
            todo.reminderDate = nil; todo.reminderOffset = 0
        case .atTime:
            todo.reminderDate = reminderAt; todo.reminderOffset = 0
        case .beforeDue:
            todo.reminderDate = nil; todo.reminderOffset = reminderOffset
        case .dailyUntilDone:
            todo.reminderDate = dailyTime; todo.reminderOffset = 0
        }
        todo.priority = priority
        todo.category = category
        context.saveOrReport()
        Task { await NotificationManager.shared.reschedule(todo: todo) }
        dismiss()
    }
}
