import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived })
    private var tasks: [TaskItem]

    @State private var month: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                monthGrid
                Divider().padding(.horizontal)
                dayDetail
            }
            .padding(.vertical)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(orderedWeekdaySymbols(), id: \.self) { symbol in
                Text(symbol).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Grid

    private var monthGrid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    DayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDay),
                        isToday: calendar.isDateInToday(date),
                        scheduledCount: scheduledTasks(on: date).count,
                        completedCount: scheduledTasks(on: date).filter { $0.isCompleted(on: date) }.count
                    )
                    .onTapGesture { selectedDay = date }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Day detail

    private var dayDetail: some View {
        let items = scheduledTasks(on: selectedDay)
        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedDay.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)
                .padding(.horizontal)
            if items.isEmpty {
                Text("Nothing scheduled.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(items) { task in
                    TaskRow(task: task, day: selectedDay, toggle: { toggle(task, on: selectedDay) })
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func scheduledTasks(on day: Date) -> [TaskItem] {
        tasks.filter { SchedulingEngine.isScheduled($0, on: day) }
    }

    private func toggle(_ task: TaskItem, on day: Date) {
        if let existing = task.completion(on: day) {
            context.delete(existing)
        } else {
            context.insert(Completion(scheduledDate: day, status: .done, task: task))
        }
        try? context.save()
    }

    private func shiftMonth(_ delta: Int) {
        if let new = calendar.date(byAdding: .month, value: delta, to: month) {
            month = new
        }
    }

    /// Builds an array of 42 slots (6 weeks); `nil` for leading/trailing padding.
    private func monthDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let firstWeekday = calendar.dateComponents([.weekday], from: interval.start).weekday
        else { return [] }

        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        var slots: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<daysInMonth {
            slots.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while slots.count % 7 != 0 { slots.append(nil) }
        return slots
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let scheduledCount: Int
    let completedCount: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
            HStack(spacing: 2) {
                if scheduledCount > 0 {
                    Circle()
                        .fill(completedCount == scheduledCount ? Color.green : Color.accentColor)
                        .frame(width: 5, height: 5)
                    if scheduledCount > 1 {
                        Text("\(scheduledCount)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                } else {
                    Circle().fill(.clear).frame(width: 5, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack { CalendarView() }
        .modelContainer(PreviewData.container)
}
