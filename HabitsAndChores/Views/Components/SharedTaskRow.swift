import SwiftUI

/// A row for a shared household chore (recurring), shown in the normal Today and
/// Tasks lists alongside private tasks. Carries a small house badge plus the
/// household name and assignee, and a completion toggle.
struct SharedTaskRow: View {
    let chore: SharedChore
    let householdName: String
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chore.symbolName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color(hue: chore.colorHue, saturation: 0.65, brightness: 0.9),
                            in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                    .strikethrough(chore.isDone, color: .secondary)
                    .foregroundStyle(chore.isDone ? .secondary : .primary)
                HStack(spacing: 4) {
                    Image(systemName: "house.fill").font(.caption2)
                    if chore.hasMultipleAssignees {
                        // Per-person check-off: show progress instead of a single owner.
                        Text("\(householdName) · \(chore.frequency.localizedDescription) · \(chore.progressSummary)")
                    } else if chore.isDone, let by = chore.completedBy {
                        Text("\(householdName) · Done by \(by)")
                    } else if let summary = chore.assigneeSummary() {
                        Text("\(householdName) · \(chore.frequency.localizedDescription) · \(summary)")
                    } else {
                        Text("\(householdName) · \(chore.frequency.localizedDescription)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: toggle) {
                Image(systemName: chore.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(chore.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}
