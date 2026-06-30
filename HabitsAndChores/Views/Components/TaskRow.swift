import SwiftUI

/// A single task row with an icon, title/frequency, and a completion toggle.
/// Pass `onTap` to make the label area open an editor (the toggle stays independent).
struct TaskRow: View {
    let task: TaskItem
    let day: Date
    let toggle: () -> Void
    var onTap: (() -> Void)? = nil

    private var isDone: Bool { task.isCompleted(on: day) }
    private var streak: Int { SchedulingEngine.currentStreak(for: task, asOf: day) }

    var body: some View {
        HStack(spacing: 12) {
            if let onTap {
                Button(action: onTap) { rowLabel }
                    .buttonStyle(.plain)
            } else {
                rowLabel
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

    @ViewBuilder private var rowLabel: some View {
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
        if streak > 1 {
            Label("\(streak)", systemImage: "flame.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        }
    }
}
