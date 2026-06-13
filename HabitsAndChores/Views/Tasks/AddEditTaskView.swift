import SwiftUI
import SwiftData

/// Create a new task (when `task == nil`) or edit an existing one.
struct AddEditTaskView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem?

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

    private var isEditing: Bool { task != nil }

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
                VStack(alignment: .leading) {
                    Text("Color")
                    Slider(value: $colorHue, in: 0...1)
                        .tint(Color(hue: colorHue, saturation: 0.65, brightness: 0.9))
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

            if isEditing {
                Section {
                    Button(task!.isArchived ? "Unarchive" : "Archive", role: .none) { toggleArchive() }
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
        .onAppear(perform: loadIfEditing)
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

    private func loadIfEditing() {
        guard let task else { return }
        title = task.title
        details = task.details
        kind = task.kind
        category = task.category
        symbolName = task.symbolName
        colorHue = task.colorHue
        let f = task.frequency
        freqKind = f.kind
        interval = f.interval
        unit = f.unit
        weekdays = Set(f.weekdays)
        dayOfMonth = f.dayOfMonth ?? 1
        if let h = task.reminderHour, let m = task.reminderMinute {
            reminderOn = true
            reminderTime = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now
        }
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let target: TaskItem
        if let task {
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
        target.reminderHour = reminderOn ? comps.hour : nil
        target.reminderMinute = reminderOn ? comps.minute : nil

        try? context.save()
        Task { await NotificationManager.shared.reschedule(for: target) }
        dismiss()
    }

    private func toggleArchive() {
        guard let task else { return }
        task.isArchived.toggle()
        try? context.save()
        if task.isArchived { NotificationManager.shared.cancel(taskID: task.id) }
        dismiss()
    }

    private func deleteTask() {
        guard let task else { return }
        NotificationManager.shared.cancel(taskID: task.id)
        context.delete(task)
        try? context.save()
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
}
