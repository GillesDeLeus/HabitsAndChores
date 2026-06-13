import SwiftUI
import SwiftData

/// Edit a to-do's title, due date, reminder, and priority.
struct TodoEditView: View {
    let todo: TodoItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var hasReminder: Bool
    @State private var reminder: Date
    @State private var priority: TodoPriority

    init(todo: TodoItem) {
        self.todo = todo
        let tomorrow9 = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
                                              of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now
        _title = State(initialValue: todo.title)
        _hasDue = State(initialValue: todo.dueDate != nil)
        _due = State(initialValue: todo.dueDate ?? tomorrow9)
        _hasReminder = State(initialValue: todo.reminderDate != nil)
        _reminder = State(initialValue: todo.reminderDate ?? tomorrow9)
        _priority = State(initialValue: todo.priority)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Title", text: $title) }

                Section {
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("Reminder", isOn: $hasReminder.animation())
                    if hasReminder {
                        DatePicker("Remind me", selection: $reminder)
                    }
                } footer: {
                    if hasReminder {
                        Text("You'll get a notification at this time.")
                    }
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(TodoPriority.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                }
            }
            .navigationTitle("Edit To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        todo.title = title.trimmingCharacters(in: .whitespaces)
        todo.dueDate = hasDue ? due : nil
        todo.reminderDate = hasReminder ? reminder : nil
        todo.priority = priority
        context.saveOrReport()
        Task { await NotificationManager.shared.reschedule(todo: todo) }
        dismiss()
    }
}
