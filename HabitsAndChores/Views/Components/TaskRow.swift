import SwiftUI

/// A single task row with an icon, title/frequency, and a completion toggle.
struct TaskRow: View {
    let task: TaskItem
    let day: Date
    let toggle: () -> Void

    private var isDone: Bool { task.isCompleted(on: day) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.symbolName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(task.color, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Text(task.frequency.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Streak as of the row's day (not always "now"), so the calendar shows the
            // streak for the day you're viewing rather than a today-relative number.
            let streak = SchedulingEngine.currentStreak(for: task, asOf: day)
            if streak > 1 {
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }

            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}
