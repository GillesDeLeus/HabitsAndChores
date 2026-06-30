import SwiftUI
import CloudKit

struct HouseholdDetailView: View {
    let householdID: String
    @Bindable var model: HouseholdsModel
    @Environment(\.dismiss) private var dismiss

    @State private var sharePresentation: SharePresentation?
    @State private var showAddFriends = false
    @State private var choreToEdit: SharedChore?
    @State private var confirmingLeave = false

    private var household: Household? {
        model.households.first { $0.id == householdID }
    }

    var body: some View {
        Group {
            if let household {
                content(household)
            } else {
                ContentUnavailableView("Household unavailable", systemImage: "house.slash")
            }
        }
        .sheet(item: $sharePresentation) { presentation in
            HouseholdShareSheet(share: presentation.share, container: presentation.container)
        }
    }

    private func content(_ household: Household) -> some View {
        List {
            Section("Chores") {
                if household.chores.isEmpty {
                    Text("Tasks assigned to this household show up here. Add one from the Tasks or To-Do tab and pick this household.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(household.chores) { chore in
                        ChoreRow(chore: chore) {
                            model.setDone(chore, in: household, !chore.isDone)
                        } edit: {
                            choreToEdit = chore
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { household.chores[$0] }.forEach { model.delete($0, in: household) }
                    }
                }
            }

            Section("Members") {
                ForEach(household.members) { member in
                    HStack(spacing: 10) {
                        AvatarView(config: member.avatarConfig, fallbackText: member.name, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                            if member.isOwner && member.hasResolvedName {
                                Text(member.isCurrentUser ? "Owner · You" : "Owner")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if member.isCurrentUser {
                                Text("You").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        // The owner can remove any other member.
                        if household.isOwner && !member.isOwner && !member.isCurrentUser {
                            Button(role: .destructive) {
                                model.removeMember(member, from: household)
                            } label: { Label("Remove", systemImage: "person.fill.xmark") }
                        }
                    }
                }
                if household.isOwner {
                    Button { showAddFriends = true } label: {
                        Label("Invite friends", systemImage: "person.2.badge.plus")
                    }
                    Button { invite(household) } label: {
                        Label("Invite by link", systemImage: "link")
                    }
                }
            }

            Section {
                NavigationLink {
                    HouseholdHistoryView(householdID: household.id, model: model)
                } label: {
                    Label("Fairness & activity", systemImage: "chart.bar.xaxis")
                }
            }

            Section {
                Button(role: .destructive) { confirmingLeave = true } label: {
                    Label(household.isOwner ? "Delete household" : "Leave household",
                          systemImage: household.isOwner ? "trash" : "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text(household.isOwner
                     ? "Deleting removes the household and its tasks for everyone."
                     : "Leaving removes the household from your devices. The owner and other members keep it.")
            }
        }
        .navigationTitle(household.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(household.isOwner ? "Delete this household for everyone?" : "Leave this household?",
                            isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button(household.isOwner ? "Delete" : "Leave", role: .destructive) {
                model.delete(household)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $choreToEdit) { chore in
            if chore.isTodo {
                TodoEditView(subject: .shared(household, chore))
            } else {
                NavigationStack { AddEditTaskView(shared: chore, in: household) }
            }
        }
        .sheet(isPresented: $showAddFriends) {
            AddFriendsToHouseholdView { friend in
                await model.invite(friend, to: household)
            }
        }
    }

    private func invite(_ household: Household) {
        Task {
            if let (share, container) = await model.share(for: household) {
                sharePresentation = SharePresentation(share: share, container: container)
            }
        }
    }
}

private struct ChoreRow: View {
    let chore: SharedChore
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: chore.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chore.isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: edit) {
                HStack(spacing: 12) {
                    Image(systemName: chore.symbolName)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color(hue: chore.colorHue, saturation: 0.65, brightness: 0.9),
                                    in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chore.title)
                            .strikethrough(chore.isDone, color: .secondary)
                            .foregroundStyle(chore.isDone ? .secondary : .primary)
                        HStack(spacing: 6) {
                            if chore.hasMultipleAssignees {
                                // Per-person check-off: overall progress across assignees.
                                Text(chore.frequency.localizedDescription)
                                Text("· \(chore.progressSummary)")
                            } else if chore.isDone, let by = chore.completedBy {
                                Text("Done by \(by)")
                            } else {
                                Text(chore.frequency.localizedDescription)
                                if let summary = chore.assigneeSummary() {
                                    Text("· \(summary)")
                                }
                                if chore.rotates {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .accessibilityLabel("Rotates between members")
                                }
                            }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
