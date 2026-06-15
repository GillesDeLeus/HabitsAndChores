import SwiftUI
import SwiftData

/// Create a new task or edit an existing one. Handles both a private local
/// `TaskItem` and a shared household chore (a `SharedChore` in a household zone);
/// the Household picker can also move a task between the two stores.
struct AddEditTaskView: View {
    /// What this editor is editing: a private local task (nil = brand new) or an
    /// existing shared household chore.
    enum Subject {
        case task(TaskItem?)
        case shared(Household, SharedChore)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HouseholdsModel.self) private var households

    let subject: Subject

    /// Existing entry point: create (`nil`) or edit a private local task.
    init(task: TaskItem?) { self.subject = .task(task) }
    /// Edit an existing shared household chore.
    init(shared chore: SharedChore, in household: Household) { self.subject = .shared(household, chore) }

    @State private var title = ""
    @State private var details = ""
    @State private var kind: TaskKind = .chore
    @State private var category: TaskCategory = .home
    @State private var symbolName = "house.fill"
    @State private var colorHue: Double = 0.58

    // Frequency
    @State private var freqKind: FrequencyRule.Kind = .daily
    @State private var interval = 1
    @State private var unit: FrequencyRule.Unit = .day
    @State private var weekdays: Set<Int> = [Calendar.current.component(.weekday, from: .now)]
    @State private var dayOfMonth = 1

    // Reminder
    @State private var reminderOn = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now

    // Sharing
    @State private var householdID: String?     // nil = Private
    @State private var assignee: String?
    @State private var rotates = false
    @State private var loaded = false

    /// The household this task currently lives in (its origin), or nil if private.
    private var originHouseholdID: String? {
        if case let .shared(household, _) = subject { return household.id }
        return nil
    }
    private var existingTask: TaskItem? {
        if case let .task(task) = subject { return task }
        return nil
    }
    private var existingShared: (Household, SharedChore)? {
        if case let .shared(household, chore) = subject { return (household, chore) }
        return nil
    }
    private var isEditing: Bool {
        switch subject {
        case .task(let t): return t != nil
        case .shared:      return true
        }
    }
    private var selectedHousehold: Household? {
        householdID.flatMap { households.household($0) }
    }

    var body: some View {
        Form {
            Section(header: Text("Details")) {
                TextField("Title", text: $title)
                TextField("Description (optional)", text: $details, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Type", selection: $kind) {
                    ForEach(TaskKind.allCases) { Text($0.localizedName).tag($0) }
                }
                Picker("Category", selection: $category) {
                    ForEach(TaskCategory.allCases) { cat in
                        Label(cat.localizedName, systemImage: cat.symbolName).tag(cat)
                    }
                }
            }

            Section(header: Text("Appearance")) {
                IconPicker(selection: $symbolName)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                    ColorSwatchPicker(selection: $colorHue)
                }
            }

            Section(header: Text("Frequency")) {
                Picker("Repeats", selection: $freqKind) {
                    Text("Daily").tag(FrequencyRule.Kind.daily)
                    Text("Weekly").tag(FrequencyRule.Kind.weekly)
                    Text("Monthly").tag(FrequencyRule.Kind.monthly)
                    Text("Every N").tag(FrequencyRule.Kind.everyN)
                }
                frequencyDetail
            }

            Section(header: Text("Reminder")) {
                Toggle("Remind me", isOn: $reminderOn)
                if reminderOn {
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            }

            Section {
                Picker("Household", selection: $householdID) {
                    Text("Private").tag(String?.none)
                    ForEach(households.households) { Text($0.name).tag(String?.some($0.id)) }
                }
                if let household = selectedHousehold {
                    Picker("Assignee", selection: $assignee) {
                        Text("Unassigned").tag(String?.none)
                        ForEach(household.members) { Text($0.name).tag(String?.some($0.name)) }
                    }
                    Toggle("Rotate between members", isOn: $rotates)
                }
            } header: {
                Text("Sharing")
            } footer: {
                if householdID == nil {
                    Text("Private tasks stay on your devices. Choose a household to share and assign this task.")
                } else if rotates {
                    Text("After each completion this chore passes to the next member automatically. The assignee above is who's up first.")
                } else {
                    Text("Shared with everyone in the household. Moving a task between Private and a household resets its completion history.")
                }
            }

            if isEditing {
                Section {
                    if let task = existingTask {
                        Button(task.isArchived ? "Unarchive" : "Archive") { toggleArchive() }
                    }
                    Button("Delete", role: .destructive) { deleteTask() }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Task" : "New Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    @ViewBuilder
    private var frequencyDetail: some View {
        switch freqKind {
        case .daily:
            EmptyView()
        case .weekly:
            WeekdaySelector(selection: $weekdays)
        case .monthly:
            Stepper("On day \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
        case .everyN:
            Stepper("Every \(interval)", value: $interval, in: 1...60)
            Picker("Unit", selection: $unit) {
                Text("Days").tag(FrequencyRule.Unit.day)
                Text("Weeks").tag(FrequencyRule.Unit.week)
                Text("Months").tag(FrequencyRule.Unit.month)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Build frequency

    private func buildFrequency() -> FrequencyRule {
        switch freqKind {
        case .daily:   return .daily
        case .weekly:  return .weekly(on: Array(weekdays))
        case .monthly: return .monthly(day: dayOfMonth)
        case .everyN:  return .every(interval, unit)
        }
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        switch subject {
        case .task(let task):
            guard let task else { return }
            apply(title: task.title, details: task.details, kind: task.kind, category: task.category,
                  symbolName: task.symbolName, colorHue: task.colorHue, frequency: task.frequency,
                  reminderHour: task.reminderHour, reminderMinute: task.reminderMinute,
                  householdID: nil, assignee: nil, rotates: false)
        case .shared(let household, let chore):
            apply(title: chore.title, details: chore.details, kind: chore.kind, category: chore.category,
                  symbolName: chore.symbolName, colorHue: chore.colorHue, frequency: chore.frequency,
                  reminderHour: chore.reminderHour, reminderMinute: chore.reminderMinute,
                  householdID: household.id, assignee: chore.assignee, rotates: chore.rotates)
        }
    }

    private func apply(title: String, details: String, kind: TaskKind, category: TaskCategory,
                       symbolName: String, colorHue: Double, frequency f: FrequencyRule,
                       reminderHour: Int?, reminderMinute: Int?, householdID: String?,
                       assignee: String?, rotates: Bool) {
        self.title = title
        self.details = details
        self.kind = kind
        self.category = category
        self.symbolName = symbolName
        self.colorHue = colorHue
        freqKind = f.kind
        interval = f.interval
        unit = f.unit
        weekdays = Set(f.weekdays.isEmpty ? [Calendar.current.component(.weekday, from: .now)] : f.weekdays)
        dayOfMonth = f.dayOfMonth ?? 1
        if let h = reminderHour, let m = reminderMinute {
            reminderOn = true
            reminderTime = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now
        }
        self.householdID = householdID
        self.assignee = assignee
        self.rotates = rotates
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let hour = reminderOn ? comps.hour : nil
        let minute = reminderOn ? comps.minute : nil

        // Destination: private (nil) or a still-valid selected household.
        let destination = selectedHousehold

        // 1. Remove the task from its current store if it's moving away from there.
        if let task = existingTask, destination != nil {
            // Private -> household: drop the local task.
            NotificationManager.shared.cancel(taskID: task.id)
            context.delete(task)
            context.saveOrReport()
        } else if let (origin, chore) = existingShared, destination?.id != origin.id {
            // Household -> elsewhere (private or a different household): drop the shared chore.
            households.delete(chore, in: origin)
        }

        // 2. Write to the destination store.
        if let destination {
            if let (origin, chore) = existingShared, origin.id == destination.id {
                households.updateChore(chore, draft: draft(hour: hour, minute: minute), in: destination)
            } else {
                households.addChore(to: destination, draft: draft(hour: hour, minute: minute))
            }
        } else {
            let target: TaskItem
            if let task = existingTask {
                target = task
                target.title = title
                target.details = details
                target.kindRaw = kind.rawValue
                target.categoryRaw = category.rawValue
                target.symbolName = symbolName
                target.colorHue = colorHue
                target.frequency = buildFrequency()
            } else {
                target = TaskItem(title: title, details: details, kind: kind, category: category,
                                  frequency: buildFrequency(), symbolName: symbolName, colorHue: colorHue)
                context.insert(target)
            }
            target.reminderHour = hour
            target.reminderMinute = minute
            context.saveOrReport()
            Task { await NotificationManager.shared.reschedule(for: target) }
        }
        dismiss()
    }

    private func draft(hour: Int?, minute: Int?) -> ChoreDraft {
        var draft = ChoreDraft()
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.details = details
        draft.kind = kind
        draft.category = category
        draft.symbolName = symbolName
        draft.colorHue = colorHue
        draft.frequency = buildFrequency()
        draft.assignee = assignee
        draft.reminderHour = hour
        draft.reminderMinute = minute
        draft.rotates = rotates
        return draft
    }

    private func toggleArchive() {
        guard let task = existingTask else { return }
        task.isArchived.toggle()
        context.saveOrReport()
        if task.isArchived { NotificationManager.shared.cancel(taskID: task.id) }
        dismiss()
    }

    private func deleteTask() {
        if let task = existingTask {
            NotificationManager.shared.cancel(taskID: task.id)
            context.delete(task)
            context.saveOrReport()
        } else if let (household, chore) = existingShared {
            households.delete(chore, in: household)
        }
        dismiss()
    }
}

// MARK: - Sub-pickers

private struct WeekdaySelector: View {
    @Binding var selection: Set<Int>
    private let symbols = Calendar.current.shortWeekdaySymbols // index 0 == Sunday

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Text(symbols[weekday - 1].prefix(1))
                    .font(.caption.bold())
                    .frame(width: 34, height: 34)
                    .background(isOn ? Color.accentColor : Color.gray.opacity(0.15), in: Circle())
                    .foregroundStyle(isOn ? .white : .primary)
                    .onTapGesture {
                        if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A grid of preset colour swatches (replacing the hue slider). Stores the chosen
/// hue; swatches render at the app's fixed saturation/brightness so the picker is
/// WYSIWYG with how tasks actually display.
private struct ColorSwatchPicker: View {
    @Binding var selection: Double

    // Evenly spread, hand-tuned hues spanning the spectrum.
    private let hues: [Double] = [0.00, 0.04, 0.08, 0.13, 0.25, 0.33,
                                  0.45, 0.50, 0.58, 0.66, 0.75, 0.83, 0.92]
    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    /// Index of the swatch closest to the current hue (so an existing arbitrary hue
    /// still shows a selection).
    private var selectedIndex: Int {
        hues.indices.min(by: { abs(hues[$0] - selection) < abs(hues[$1] - selection) }) ?? 0
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(hues.indices, id: \.self) { i in
                Circle()
                    .fill(Color(hue: hues[i], saturation: 0.65, brightness: 0.9))
                    .frame(width: 34, height: 34)
                    .overlay {
                        if i == selectedIndex {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(i == selectedIndex ? 0.5 : 0), lineWidth: 2)
                    }
                    .onTapGesture { selection = hues[i] }
                    .accessibilityLabel("Colour \(i + 1)")
                    .accessibilityAddTraits(i == selectedIndex ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}

private struct IconPicker: View {
    @Binding var selection: String
    private let options = [
        "house.fill", "heart.fill", "drop.fill", "figure.run", "pills.fill",
        "trash.fill", "leaf.fill", "pawprint.fill", "book.fill", "phone.fill",
        "creditcard.fill", "calendar", "fork.knife", "moon.fill", "checklist", "star.fill"
    ]
    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { name in
                Image(systemName: name)
                    .frame(width: 36, height: 36)
                    .background(selection == name ? Color.accentColor.opacity(0.25) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { selection = name }
            }
        }
    }
}

#Preview {
    NavigationStack { AddEditTaskView(task: nil) }
        .modelContainer(PreviewData.container)
        .environment(HouseholdsModel())
}
