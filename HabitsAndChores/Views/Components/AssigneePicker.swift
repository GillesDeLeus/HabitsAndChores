import SwiftUI

/// A multi-select list of household members for assigning a shared task to one or
/// more people (per-person check-off). Used by both task and to-do editors. Selection
/// is a `Set` of member display names; empty means "unassigned / up for grabs".
struct AssigneePicker: View {
    let members: [HouseholdMember]
    @Binding var selection: Set<String>
    /// Called after every toggle, so the host can reconcile mutually-exclusive state
    /// (e.g. turn off rotation once more than one member is selected).
    var onChange: () -> Void = {}

    var body: some View {
        // A labelled, tappable row per member with a trailing checkmark. Plain buttons
        // (not a `Picker`) so several can be selected at once inside a `Form`.
        ForEach(members) { member in
            Button {
                if selection.contains(member.name) { selection.remove(member.name) }
                else { selection.insert(member.name) }
                onChange()
            } label: {
                HStack(spacing: 10) {
                    AvatarView(config: member.avatarConfig, fallbackText: member.name, size: 28)
                    Text(member.name).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(member.name) {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(selection.contains(member.name) ? .isSelected : [])
        }
    }
}

extension SharedChore {
    /// Compact assignee summary for list captions: "Anna", "Anna & Ben", or
    /// "Anna, Ben +2" once the list grows. nil when unassigned.
    func assigneeSummary(maxNames: Int = 2) -> String? {
        guard !assignees.isEmpty else { return nil }
        let names = assignees.sorted()
        if names.count <= maxNames { return names.formatted(.list(type: .and)) }
        let shown = names.prefix(maxNames).formatted(.list(type: .and))
        return String(localized: "\(shown) +\(names.count - maxNames)",
                      comment: "Assignee list truncated, e.g. 'Anna, Ben +2'")
    }

    /// "2 of 3 done" progress, shown while a multi-assignee chore is partially complete.
    var progressSummary: String {
        String(localized: "\(completedAssigneeCount) of \(assigneeTarget) done",
               comment: "Per-person completion progress for a shared chore")
    }
}
