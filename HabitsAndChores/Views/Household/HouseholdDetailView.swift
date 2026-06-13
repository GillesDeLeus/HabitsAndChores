import SwiftUI
import CloudKit

struct HouseholdDetailView: View {
    let householdID: String
    @Bindable var model: HouseholdsModel

    @State private var newChore = ""
    @State private var sharePresentation: SharePresentation?
    @State private var showAddFriends = false
    @State private var inviteAfterAdd = false

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
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    TextField("Add a chore", text: $newChore)
                        .onSubmit { addChore(household) }
                        .submitLabel(.done)
                }
            }

            Section("Chores") {
                if household.chores.isEmpty {
                    Text("No chores yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(household.chores) { chore in
                        ChoreRow(chore: chore, members: household.members,
                                 toggle: { Task { await model.setDone(chore, in: household, !chore.isDone) } },
                                 assign: { member in Task { await model.assign(chore, to: member, in: household) } })
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { household.chores[$0] }
                        Task { for chore in targets { await model.delete(chore, in: household) } }
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
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

    private func addChore(_ household: Household) {
        let title = newChore.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newChore = ""
        Task { await model.addChore(to: household, title: title) }
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
    let members: [String]
    let toggle: () -> Void
    let assign: (String?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: chore.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chore.isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                    .strikethrough(chore.isDone, color: .secondary)
                    .foregroundStyle(chore.isDone ? .secondary : .primary)
                if let assignee = chore.assignee {
                    Label(assignee, systemImage: "person.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()

            Menu {
                Button("Unassigned") { assign(nil) }
                ForEach(members, id: \.self) { member in
                    Button(member) { assign(member) }
                }
            } label: {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Assign chore")
        }
    }
}
