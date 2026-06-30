import SwiftUI
import SwiftData

/// Create or edit a to-do's title, due date, reminder, and priority. Handles both
/// a private local `TodoItem` and a shared household to-do (a `SharedChore` with
/// `isTodo == true`); the Household picker can also move it between the two stores.
struct TodoEditView: View {
    /// What this editor is editing: a private local to-do (nil = brand new) or an
    /// existing shared household to-do.
    enum Subject {
        case todo(TodoItem?)
        case shared(Household, SharedChore)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HouseholdsModel.self) private var households

    let subject: Subject

    /// Edit an existing private to-do.
    init(todo: TodoItem) { self.subject = .todo(todo) }
    /// Create a new to-do, or edit a shared one.
    init(subject: Subject) { self.subject = subject }

    @State private var title = ""
    @State private var details = ""
    @State private var hasDue = false
    @State private var due = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
        of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now
    @State private var hasSchedule = false
    @State private var scheduled = Calendar.current.startOfDay(for: .now)
    @State private var reminderMode: TodoReminderMode = .none
    @State private var reminderAt = Date.now
    @State private var reminderOffset: Double = 0
    @State private var dailyTime = Date.now
    @State private var priority: TodoPriority = .none
    @State private var category: TaskCategory?

    // Sharing
    @State private var householdID: String?     // nil = Private
    @State private var assignees: Set<String> = []   // member names; empty = unassigned
    @State private var loaded = false

    private var existingTodo: TodoItem? {
        if case let .todo(todo) = subject { return todo }
        return nil
    }
    private var existingShared: (Household, SharedChore)? {
        if case let .shared(household, chore) = subject { return (household, chore) }
        return nil
    }
    private var isEditing: Bool {
        switch subject {
        case .todo(let t): return t != nil
        case .shared:      return true
        }
    }
    private var selectedHousehold: Household? {
        householdID.flatMap { households.household($0) }
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
                } footer: {
                    Text("The deadline this needs to be done by.")
                }

                // Scheduling (a planned "do" day) applies to both private and shared to-dos.
                Section {
                    Toggle("Schedule for a day", isOn: $hasSchedule.animation())
                    if hasSchedule {
                        DatePicker("Do on", selection: $scheduled, displayedComponents: .date)
                    }
                } footer: {
                    Text(householdID == nil
                         ? "The day you plan to do it — it shows up in Today on that date (and stays until you complete it)."
                         : "The day this is up — it shows in Today for whoever it's assigned to (or everyone, if unassigned) on that date.")
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

                Section {
                    Picker("Household", selection: $householdID) {
                        Text("Private").tag(String?.none)
                        ForEach(households.households) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    if let household = selectedHousehold {
                        AssigneePicker(members: household.members, selection: $assignees)
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    if householdID == nil {
                        Text("Private to-dos stay on your devices. Choose a household to share and assign this to-do.")
                    } else if assignees.count > 1 {
                        Text("Each assignee gets their own checkbox — the to-do is done once everyone has completed it.")
                    } else {
                        Text("Shared with everyone in the household. Moving a to-do between Private and a household resets its done state.")
                    }
                }

                if isEditing {
                    Section {
                        Button("Delete", role: .destructive) { deleteTodo() }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit To-Do" : "New To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadIfNeeded)
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

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        switch subject {
        case .todo(let todo):
            guard let todo else { return }
            title = todo.title
            details = todo.details
            hasDue = todo.dueDate != nil
            if let d = todo.dueDate { due = d }
            reminderMode = todo.reminderMode
            if let r = todo.reminderDate { reminderAt = r; dailyTime = r }
            reminderOffset = todo.reminderOffset
            priority = todo.priority
            category = todo.category
            hasSchedule = todo.scheduledDate != nil
            if let s = todo.scheduledDate { scheduled = s }
        case .shared(let household, let chore):
            title = chore.title
            details = chore.details
            hasDue = chore.dueDate != nil
            if let d = chore.dueDate { due = d }
            reminderMode = chore.todoReminderMode
            if let r = chore.reminderDate { reminderAt = r; dailyTime = r }
            reminderOffset = chore.reminderOffset
            priority = chore.priority
            category = chore.categoryRaw.isEmpty ? nil : TaskCategory(rawValue: chore.categoryRaw)
            hasSchedule = chore.scheduledDate != nil
            if let s = chore.scheduledDate { scheduled = s }
            householdID = household.id
            assignees = Set(chore.assignees)
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let destination = selectedHousehold

        // 1. Remove from the current store if moving away.
        if let todo = existingTodo, destination != nil {
            NotificationManager.shared.cancelTodo(id: todo.id)
            context.delete(todo)
            context.saveOrReport()
        } else if let (origin, chore) = existingShared, destination?.id != origin.id {
            households.delete(chore, in: origin)
        }

        // 2. Write to the destination store.
        if let destination {
            if let (origin, chore) = existingShared, origin.id == destination.id {
                households.updateChore(chore, draft: buildDraft(), in: destination)
            } else {
                households.addChore(to: destination, draft: buildDraft())
            }
        } else if let todo = existingTodo {
            applyTo(todo, title: trimmedTitle)
            context.saveOrReport()
            Task { await NotificationManager.shared.reschedule(todo: todo) }
        } else {
            // New private to-do: goes to the top of the open list.
            let todo = TodoItem(title: trimmedTitle)
            context.insert(todo)
            applyTo(todo, title: trimmedTitle)
            context.saveOrReport()
            Task { await NotificationManager.shared.reschedule(todo: todo) }
        }
        dismiss()
    }

    /// Resolved reminder mode (clears "before due" when there's no due date).
    private var resolvedReminderMode: TodoReminderMode {
        (reminderMode == .beforeDue && !hasDue) ? .none : reminderMode
    }

    private func applyTo(_ todo: TodoItem, title: String) {
        todo.title = title
        todo.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.dueDate = hasDue ? due : nil
        todo.reminderMode = resolvedReminderMode
        switch todo.reminderMode {
        case .none:           todo.reminderDate = nil;       todo.reminderOffset = 0
        case .atTime:         todo.reminderDate = reminderAt; todo.reminderOffset = 0
        case .beforeDue:      todo.reminderDate = nil;       todo.reminderOffset = reminderOffset
        case .dailyUntilDone: todo.reminderDate = dailyTime;  todo.reminderOffset = 0
        }
        todo.priority = priority
        todo.category = category
        todo.scheduledDate = hasSchedule ? Calendar.current.startOfDay(for: scheduled) : nil
    }

    private func buildDraft() -> ChoreDraft {
        var draft = ChoreDraft()
        draft.isTodo = true
        draft.title = title.trimmingCharacters(in: .whitespaces)
        draft.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.symbolName = "checklist"
        draft.category = category ?? .other
        draft.dueDate = hasDue ? due : nil
        draft.scheduledDate = hasSchedule ? Calendar.current.startOfDay(for: scheduled) : nil
        draft.priority = priority
        draft.assignees = assignees.sorted()
        let mode = resolvedReminderMode
        draft.todoReminderMode = mode
        switch mode {
        case .none:           draft.reminderDate = nil;        draft.reminderOffset = 0
        case .atTime:         draft.reminderDate = reminderAt;  draft.reminderOffset = 0
        case .beforeDue:      draft.reminderDate = nil;        draft.reminderOffset = reminderOffset
        case .dailyUntilDone: draft.reminderDate = dailyTime;   draft.reminderOffset = 0
        }
        return draft
    }

    private func deleteTodo() {
        if let todo = existingTodo {
            NotificationManager.shared.cancelTodo(id: todo.id)
            context.delete(todo)
            context.saveOrReport()
        } else if let (household, chore) = existingShared {
            households.delete(chore, in: household)
        }
        dismiss()
    }
}
