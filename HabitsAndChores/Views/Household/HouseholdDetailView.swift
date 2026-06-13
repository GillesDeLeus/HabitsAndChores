import SwiftUI
import CloudKit

struct HouseholdDetailView: View {
    let householdID: String
    @Bindable var model: HouseholdsModel

    @State private var sharePresentation: SharePresentation?
    @State private var showAddFriends = false
    @State private var inviteAfterAdd = false
    @State private var addingChore = false
    @State private var choreToEdit: SharedChore?

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
                    Text("No chores yet. Tap + to add one.").font(.callout).foregroundStyle(.secondary)
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
                ForEach(household.members, id: \.self) { Text($0) }
                if household.isOwner {
                    Button { showAddFriends = true } label: {
                        Label("Add from friends", systemImage: "person.2.badge.plus")
                    }
                    Button { invite(household) } label: {
                        Label("Invite by link", systemImage: "link")
                    }
                }
            }
        }
        .navigationTitle(household.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingChore = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add chore")
            }
        }
        .sheet(isPresented: $addingChore) {
            HouseholdChoreEditView(members: household.members, existing: nil) { draft in
                model.addChore(to: household, draft: draft)
            }
        }
        .sheet(item: $choreToEdit) { chore in
            HouseholdChoreEditView(members: household.members, existing: chore) { draft in
                model.updateChore(chore, draft: draft, in: household)
            }
        }
        .sheet(isPresented: $showAddFriends, onDismiss: {
            if inviteAfterAdd { inviteAfterAdd = false; invite(household) }
        }) {
            AddFriendsToHouseholdView(onAdd: { friend in
                await model.addFriend(friend, to: household)
            }, onAdded: {
                inviteAfterAdd = true
            })
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
                            if chore.isDone, let by = chore.completedBy {
                                Text("Done by \(by)")
                            } else {
                                Text(chore.frequency.localizedDescription)
                                if let assignee = chore.assignee {
                                    Text("· \(assignee)")
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
