import SwiftUI

/// Create or edit a household chore — a full habit/chore with recurrence, icon,
/// colour and an assignee, mirroring the app's own task editor.
struct HouseholdChoreEditView: View {
    let members: [String]
    let existing: SharedChore?
    let onSave: (ChoreDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft: ChoreDraft
    @State private var freqKind: FrequencyRule.Kind
    @State private var interval: Int
    @State private var unit: FrequencyRule.Unit
    @State private var weekdays: Set<Int>
    @State private var dayOfMonth: Int

    private let icons = ["house.fill", "trash.fill", "fork.knife", "cart.fill", "leaf.fill",
                         "pawprint.fill", "heart.fill", "drop.fill", "figure.run", "book.fill",
                         "creditcard.fill", "wrench.and.screwdriver.fill", "sparkles", "bed.double.fill",
                         "tshirt.fill", "checklist"]
    private let iconColumns = Array(repeating: GridItem(.flexible()), count: 6)

    init(members: [String], existing: SharedChore?, onSave: @escaping (ChoreDraft) -> Void) {
        self.members = members
        self.existing = existing
        self.onSave = onSave
        let draft = existing.map { ChoreDraft($0) } ?? ChoreDraft()
        _draft = State(initialValue: draft)
        let f = draft.frequency
        _freqKind = State(initialValue: f.kind)
        _interval = State(initialValue: f.interval)
        _unit = State(initialValue: f.unit)
        _weekdays = State(initialValue: Set(f.weekdays.isEmpty
            ? [Calendar.current.component(.weekday, from: .now)] : f.weekdays))
        _dayOfMonth = State(initialValue: f.dayOfMonth ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $draft.title)
                    TextField("Notes (optional)", text: $draft.details, axis: .vertical).lineLimit(1...3)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(TaskKind.allCases) { Text($0.localizedName).tag($0) }
                    }
                    Picker("Category", selection: $draft.category) {
                        ForEach(TaskCategory.allCases) { Label($0.localizedName, systemImage: $0.symbolName).tag($0) }
                    }
                }

                Section("Appearance") {
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(icons, id: \.self) { name in
                            Image(systemName: name)
                                .frame(width: 36, height: 36)
                                .background(draft.symbolName == name ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { draft.symbolName = name }
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Colour")
                        Slider(value: $draft.colorHue, in: 0...1)
                            .tint(Color(hue: draft.colorHue, saturation: 0.65, brightness: 0.9))
                    }
                }

                Section("Repeats") {
                    Picker("Repeats", selection: $freqKind) {
                        Text("Daily").tag(FrequencyRule.Kind.daily)
                        Text("Weekly").tag(FrequencyRule.Kind.weekly)
                        Text("Monthly").tag(FrequencyRule.Kind.monthly)
                        Text("Every N").tag(FrequencyRule.Kind.everyN)
                    }
                    frequencyDetail
                }

                Section("Assigned to") {
                    Picker("Member", selection: $draft.assignee) {
                        Text("Unassigned").tag(String?.none)
                        ForEach(members, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New chore" : "Edit chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var frequencyDetail: some View {
        switch freqKind {
        case .daily:
            EmptyView()
        case .weekly:
            HStack {
                ForEach(1...7, id: \.self) { weekday in
                    let on = weekdays.contains(weekday)
                    Text(Calendar.current.shortWeekdaySymbols[weekday - 1].prefix(1))
                        .font(.caption.bold())
                        .frame(width: 32, height: 32)
                        .background(on ? Color.accentColor : Color.gray.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                        .onTapGesture { if on { weekdays.remove(weekday) } else { weekdays.insert(weekday) } }
                }
            }
            .frame(maxWidth: .infinity)
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

    private func buildFrequency() -> FrequencyRule {
        switch freqKind {
        case .daily:   return .daily
        case .weekly:  return .weekly(on: Array(weekdays))
        case .monthly: return .monthly(day: dayOfMonth)
        case .everyN:  return .every(interval, unit)
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.frequency = buildFrequency()
        onSave(draft)
        dismiss()
    }
}
