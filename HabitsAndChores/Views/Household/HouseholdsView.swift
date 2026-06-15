import SwiftUI
import CloudKit

@MainActor
@Observable
final class HouseholdsModel {
    private let service = HouseholdService()
    private let outbox: HouseholdOutbox

    init() { outbox = HouseholdOutbox(service: service) }

    var households: [Household] = []
    var invites: [HouseholdInvite] = []     // pending invitations addressed to me
    var loading = false
    var available = true
    var error: String?

    /// Current user identity, so the owner shows their display name (not "Owner").
    var meRecordName: String?
    var meDisplayName: String = ""
    /// My social user id, used to address and fetch in-app household invitations.
    var meUserID: String?

    /// Invitations I've accepted/declined. The invite record lives in the public
    /// database and is owned by the inviter, so I can't delete it myself — I just
    /// suppress it locally so it doesn't reappear on the next fetch.
    private var dismissedInviteIDs: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "household.dismissedInvites") ?? [])

    /// Households I've left (or deleted). Leaving a CKShare server-side isn't always
    /// immediate/reliable, so I suppress these locally so a left household doesn't
    /// pop back in on the next sync. Cleared if I re-accept an invite to the same one.
    private var leftHouseholdIDs: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "household.left") ?? [])
    private func saveLeftHouseholds() {
        UserDefaults.standard.set(Array(leftHouseholdIDs), forKey: "household.left")
    }

    /// Per-database change tokens (in-memory). Let `reload()` skip the full re-fetch
    /// when nothing changed. Committed only after a successful fetch, so an errored
    /// fetch is retried rather than silently skipped.
    private var dbTokens: [CKDatabase.Scope: CKServerChangeToken] = [:]

    /// Sends any pending offline household writes, then quietly refreshes.
    func drainOutbox() async {
        guard await service.isAvailable() else { return }
        await outbox.drain()
        await refreshQuietly()
    }

    func reload() async {
        loading = true
        defer { loading = false }
        available = await service.isAvailable()
        guard available else { households = []; return }
        await outbox.drain()   // flush offline writes before re-fetching

        // Incremental: if we already have data and nothing changed, skip the full
        // re-fetch. Any error / token expiry falls back to a full fetch.
        let probe = await probeHouseholdChanges()
        if !probe.changed && !households.isEmpty {
            await loadInvites()
            return
        }
        do {
            households = try await service.households(currentUserRecordName: meRecordName,
                                                      currentUserDisplayName: meDisplayName)
                .filter { !leftHouseholdIDs.contains($0.id) }
            dbTokens = probe.tokens   // commit tokens only on a successful fetch
            error = nil
            await rescheduleSharedNotifications()
            await publishMyMemberName()
        } catch {
            self.error = error.localizedDescription
        }
        await loadInvites()
    }

    /// Probes both databases for household-zone changes since the last tokens, without
    /// committing the new tokens (the caller commits them after a successful fetch).
    private func probeHouseholdChanges() async -> (changed: Bool, tokens: [CKDatabase.Scope: CKServerChangeToken]) {
        var changed = false
        var tokens = dbTokens
        for scope in [CKDatabase.Scope.private, .shared] {
            guard let probe = try? await service.databaseChanges(scope: scope, since: dbTokens[scope]) else {
                changed = true   // on error, be safe and do the full fetch
                continue
            }
            if probe.changed { changed = true }
            if probe.expired { tokens[scope] = nil; changed = true }
            else if let token = probe.token { tokens[scope] = token }
        }
        return (changed, tokens)
    }

    /// Publishes my display name onto each household I'm in (keyed by my CloudKit
    /// user record name) so other members can see my real name instead of "Member".
    /// Only writes when missing/changed, so it's idempotent and won't loop.
    private func publishMyMemberName() async {
        guard let rn = meRecordName, !meDisplayName.isEmpty else { return }
        for household in households where household.members.contains(where: \.isCurrentUser) {
            guard household.nameByRecordName[rn] != meDisplayName else { continue }
            try? await service.publishMemberName(meDisplayName, recordName: rn, in: household)
        }
    }

    /// Loads pending in-app household invitations addressed to me, hiding ones I've
    /// already acted on or for households I've already joined.
    private func loadInvites() async {
        guard let me = meUserID else { invites = []; return }
        let fetched = (try? await service.pendingInvites(for: me)) ?? []
        let joined = Set(households.map(\.id))
        invites = fetched.filter { !dismissedInviteIDs.contains($0.id) && !joined.contains($0.householdID) }
    }

    private func markInviteDismissed(_ invite: HouseholdInvite) {
        dismissedInviteIDs.insert(invite.id)
        UserDefaults.standard.set(Array(dismissedInviteIDs), forKey: "household.dismissedInvites")
        invites.removeAll { $0.id == invite.id }
    }

    /// Invites an existing friend to a household in-app. Returns an error message,
    /// or nil on success.
    func invite(_ profile: SharedProfile, to household: Household) async -> String? {
        guard let me = meUserID else { return String(localized: "Create an account to invite friends.") }
        do {
            try await service.invite(profile, to: household, inviterUserID: me, inviterName: meDisplayName)
            await refreshQuietly()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func acceptInvite(_ invite: HouseholdInvite) {
        invites.removeAll { $0.id == invite.id }   // optimistic
        // Re-joining a household I previously left: stop suppressing it.
        leftHouseholdIDs.remove(invite.householdID); saveLeftHouseholds()
        persist {
            try await self.service.acceptInvite(invite)   // throws if the accept fails
            self.markInviteDismissed(invite)              // only suppress once it succeeded
            await self.reload()                           // the newly joined household appears
        }
    }

    func declineInvite(_ invite: HouseholdInvite) {
        // Suppress locally; best-effort delete (will no-op if I'm not the record's owner).
        markInviteDismissed(invite)
        Task { try? await service.declineInvite(invite) }
    }

    /// (Re)schedules local reminders for the shared tasks *assigned to me* that have
    /// one. Called after each sync; idempotent (cancels all shared requests first).
    private func rescheduleSharedNotifications() async {
        await NotificationManager.shared.rescheduleShared(sharedTasks(isTodo: false, .mineOnly).map(\.chore)
                                                          + sharedTasks(isTodo: true, .mineOnly).map(\.chore))
    }

    func create(name: String) async -> CKShare? {
        do {
            let share = try await service.createHousehold(name: name)
            await reload()
            return share
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: Optimistic mutations — update local state immediately, sync in the
    // background, then quietly reconcile (or revert on failure).

    /// Owner deletes the household for everyone, or a member leaves it. Either way
    /// the household is suppressed locally so it stays gone, and a leaving member's
    /// assignments are cleared so the remaining members aren't left with stale,
    /// ghost-assigned chores. (The owner deleting removes the zone — and all its
    /// tasks — for everyone, so no unassign is needed there.)
    func delete(_ household: Household) {
        leftHouseholdIDs.insert(household.id); saveLeftHouseholds()
        households.removeAll { $0.id == household.id }
        let myName = household.members.first(where: \.isCurrentUser)?.name
        persist {
            if !household.isOwner, let myName {
                try? await self.service.unassignChores(assignedTo: myName, in: household)
            }
            try await self.service.deleteHousehold(household)
        }
    }

    /// Owner removes another member: clears that member's assignments first (so no
    /// ghost-assigned chores remain), then revokes their share access.
    func removeMember(_ member: HouseholdMember, from household: Household) {
        persist {
            try? await self.service.unassignChores(assignedTo: member.name, in: household)
            try await self.service.removeMember(recordName: member.id, from: household)
        }
    }

    func addChore(to household: Household, draft: ChoreDraft) {
        // Client-assigned record name so the optimistic row and the eventual server
        // record share an id, and the queued create is idempotent.
        let recordName = UUID().uuidString
        applyLocal(household.id) { $0.append(sharedChore(id: recordName, from: draft)); $0.sort { $0.title < $1.title } }
        enqueueAndFlush(.upsertChore(opID: UUID().uuidString, zone: ZoneRef(household),
                                     householdID: household.id, recordName: recordName, draft: draft))
    }

    func updateChore(_ chore: SharedChore, draft: ChoreDraft, in household: Household) {
        applyLocal(household.id) { chores in
            guard let i = chores.firstIndex(where: { $0.id == chore.id }) else { return }
            chores[i] = sharedChore(id: chore.id, from: draft, createdAt: chore.createdAt,
                                    isDone: chore.isDone, completedBy: chore.completedBy)
            chores.sort { $0.title < $1.title }
        }
        enqueueAndFlush(.upsertChore(opID: UUID().uuidString, zone: ZoneRef(household),
                                     householdID: household.id, recordName: chore.id, draft: draft))
    }

    /// Builds a local `SharedChore` mirror of a draft (for optimistic display).
    private func sharedChore(id: String, from draft: ChoreDraft, createdAt: Date = .now,
                             isDone: Bool = false, completedBy: String? = nil) -> SharedChore {
        SharedChore(id: id, title: draft.title, details: draft.details,
                    kindRaw: draft.kind.rawValue, categoryRaw: draft.category.rawValue,
                    frequency: draft.frequency, symbolName: draft.symbolName, colorHue: draft.colorHue,
                    createdAt: createdAt, assignee: draft.assignee, isDone: isDone, completedBy: completedBy,
                    isTodo: draft.isTodo, dueDate: draft.dueDate, scheduledDate: draft.scheduledDate,
                    priorityRaw: draft.priority.rawValue, reminderModeRaw: draft.todoReminderMode.rawValue,
                    reminderDate: draft.reminderDate, reminderOffset: draft.reminderOffset,
                    reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, rotates: draft.rotates)
    }

    private func enqueueAndFlush(_ mutation: HouseholdMutation) {
        outbox.enqueue(mutation)
        flush()
    }
    private func flush() {
        Task { await outbox.drain(); await refreshQuietly() }
    }

    func setDone(_ chore: SharedChore, in household: Household, _ done: Bool) {
        let occurrence = HouseholdService.occurrence(for: chore)
        let by = meDisplayName.isEmpty ? String(localized: "Someone") : meDisplayName

        // Optional rotation: a completed rotating chore moves to the next member for
        // the next occurrence (un-completing moves it back, so toggling is symmetric).
        let rotatedAssignee = nextAssignee(for: chore, in: household, done: done)

        applyLocal(household.id) { chores in
            if let i = chores.firstIndex(where: { $0.id == chore.id }) {
                chores[i].isDone = done
                chores[i].completedBy = done ? by : nil
                if let rotatedAssignee { chores[i].assignee = rotatedAssignee }
            }
        }
        outbox.enqueue(.setCompletion(opID: UUID().uuidString, zone: ZoneRef(household),
                                      choreRecordName: chore.id, occurrence: occurrence, by: by,
                                      done: done, completionRecordName: UUID().uuidString))
        if let rotatedAssignee {
            outbox.enqueue(.assign(opID: UUID().uuidString, zone: ZoneRef(household),
                                   choreRecordName: chore.id, member: rotatedAssignee))
        }
        flush()
    }

    /// The next assignee for a rotating chore (nil if it doesn't rotate, isn't
    /// recurring, or the household has no members). Advances on completion, retreats
    /// on un-completion, using a stable alphabetical member order.
    private func nextAssignee(for chore: SharedChore, in household: Household, done: Bool) -> String? {
        guard chore.rotates, !chore.isTodo else { return nil }
        return HouseholdService.rotatedAssignee(names: household.members.map(\.name).sorted(),
                                                current: chore.assignee, done: done)
    }

    func registerSubscriptions() async { await service.registerSubscriptions() }

    /// Completion events for the fairness/activity view (newest first).
    func completionHistory(for household: Household) async -> [CompletionEvent] {
        (try? await service.completionHistory(in: household)) ?? []
    }

    /// Which shared tasks a surface wants: everything in the household, the items
    /// relevant to *me* for Today (mine or unassigned), or strictly mine.
    enum Visibility { case all, mineOrUnassigned, mineOnly }

    /// Shared tasks across my households, recurring chores (`isTodo == false`) or
    /// to-dos (`true`), filtered by `visibility`:
    /// - `.all` (default) — the whole household, for the Tasks / To-Do lists.
    /// - `.mineOrUnassigned` — for **Today**: my own plus up-for-grabs (unassigned).
    /// - `.mineOnly` — strictly assigned to me, for shared-reminder scheduling.
    func sharedTasks(isTodo: Bool, _ visibility: Visibility = .all) -> [(household: Household, chore: SharedChore)] {
        households.flatMap { household -> [(household: Household, chore: SharedChore)] in
            let myName = household.members.first(where: \.isCurrentUser)?.name
            return household.chores
                .filter { chore in
                    guard chore.isTodo == isTodo else { return false }
                    switch visibility {
                    case .all:              return true
                    case .mineOrUnassigned: return chore.assignee == nil || chore.assignee == myName
                    case .mineOnly:         return chore.assignee == myName
                    }
                }
                .map { (household, $0) }
        }
    }

    /// The household with the given id, if the user is still a member.
    func household(_ id: String) -> Household? { households.first { $0.id == id } }

    func assign(_ chore: SharedChore, to member: String?, in household: Household) {
        applyLocal(household.id) { chores in
            if let i = chores.firstIndex(where: { $0.id == chore.id }) { chores[i].assignee = member }
        }
        enqueueAndFlush(.assign(opID: UUID().uuidString, zone: ZoneRef(household),
                                choreRecordName: chore.id, member: member))
    }

    func delete(_ chore: SharedChore, in household: Household) {
        applyLocal(household.id) { $0.removeAll { $0.id == chore.id } }
        enqueueAndFlush(.deleteChore(opID: UUID().uuidString, zone: ZoneRef(household), recordName: chore.id))
    }

    func share(for household: Household) async -> (CKShare, CKContainer)? { try? await service.share(for: household) }

    private func applyLocal(_ householdID: String, _ mutate: (inout [SharedChore]) -> Void) {
        guard let index = households.firstIndex(where: { $0.id == householdID }) else { return }
        mutate(&households[index].chores)
    }

    private func persist(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            await refreshQuietly()
        }
    }

    private func refreshQuietly() async {
        guard await service.isAvailable() else { return }
        if let fresh = try? await service.households(currentUserRecordName: meRecordName,
                                                     currentUserDisplayName: meDisplayName) {
            households = fresh.filter { !leftHouseholdIDs.contains($0.id) }
            await rescheduleSharedNotifications()
        }
        await loadInvites()
    }
}

struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

struct HouseholdsView: View {
    @Environment(SocialAccount.self) private var account
    @Environment(HouseholdsModel.self) private var model
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
            if !model.invites.isEmpty {
                Section("Invitations") {
                    ForEach(model.invites) { invite in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.householdName).font(.headline)
                                Text("Invited by \(invite.inviterName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button { model.acceptInvite(invite) } label: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            .accessibilityLabel("Accept invitation to \(invite.householdName)")
                            Button { model.declineInvite(invite) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                            .accessibilityLabel("Decline invitation to \(invite.householdName)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !model.available {
                ContentUnavailableView("iCloud required", systemImage: "icloud.slash",
                                       description: Text("Sign in to iCloud to create or join a shared household."))
            } else if model.households.isEmpty && !model.loading {
                ContentUnavailableView("No households yet", systemImage: "house.and.flag",
                                       description: Text("Create one and invite your partner or housemates to share chores."))
            }
            ForEach(model.households) { household in
                NavigationLink {
                    HouseholdDetailView(householdID: household.id, model: model)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(household.name).font(.headline)
                        Text("\(household.members.count) member(s) · \(household.chores.count) chores"
                             + (household.isOwner ? "" : " · shared with you"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let targets = offsets.map { model.households[$0] }
                Task { for household in targets { await model.delete(household) } }
            }
            if let error = model.error {
                Section { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Households")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New household")
                    .disabled(!model.available)
            }
        }
        .overlay { if model.loading && model.households.isEmpty { ProgressView() } }
        .refreshable { await model.reload() }
        .task {
            model.meRecordName = account.cloudUserRecordName
            model.meDisplayName = account.displayName
            model.meUserID = account.userID
            await model.registerSubscriptions()
            await model.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .householdsChanged)) { _ in
            Task { await model.reload() }
        }
        .alert("New household", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("e.g. “Home” or “Flat 3B”. Open it to add friends or invite by link.")
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newName = ""
        Task { _ = await model.create(name: name) }
    }
}
