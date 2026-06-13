import SwiftUI
import CloudKit

@MainActor
@Observable
final class HouseholdsModel {
    private let service = HouseholdService()

    var households: [Household] = []
    var loading = false
    var available = true
    var error: String?

    /// Current user identity, so the owner shows their display name (not "Owner").
    var meRecordName: String?
    var meDisplayName: String = ""

    func reload() async {
        loading = true
        defer { loading = false }
        available = await service.isAvailable()
        guard available else { households = []; return }
        do {
            households = try await service.households(currentUserRecordName: meRecordName,
                                                      currentUserDisplayName: meDisplayName)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
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

    func delete(_ household: Household) {
        households.removeAll { $0.id == household.id }
        persist { try await self.service.deleteHousehold(household) }
    }

    func addChore(to household: Household, draft: ChoreDraft) {
        let temp = SharedChore(id: "temp-\(UUID().uuidString)", title: draft.title, details: draft.details,
                               kindRaw: draft.kind.rawValue, categoryRaw: draft.category.rawValue,
                               frequency: draft.frequency, symbolName: draft.symbolName,
                               colorHue: draft.colorHue, createdAt: .now, assignee: draft.assignee,
                               isDone: false, completedBy: nil)
        applyLocal(household.id) { $0.append(temp); $0.sort { $0.title < $1.title } }
        persist { try await self.service.addChore(to: household, draft: draft) }
    }

    func updateChore(_ chore: SharedChore, draft: ChoreDraft, in household: Household) {
        applyLocal(household.id) { chores in
            guard let i = chores.firstIndex(where: { $0.id == chore.id }) else { return }
            chores[i].title = draft.title; chores[i].details = draft.details
            chores[i].kindRaw = draft.kind.rawValue; chores[i].categoryRaw = draft.category.rawValue
            chores[i].frequency = draft.frequency; chores[i].symbolName = draft.symbolName
            chores[i].colorHue = draft.colorHue; chores[i].assignee = draft.assignee
            chores.sort { $0.title < $1.title }
        }
        persist { try await self.service.updateChore(chore, draft: draft, in: household) }
    }

    func setDone(_ chore: SharedChore, in household: Household, _ done: Bool) {
        let occurrence = HouseholdService.currentOccurrence(for: chore.frequency, anchor: chore.createdAt)
        let by = meDisplayName.isEmpty ? String(localized: "Someone") : meDisplayName
        applyLocal(household.id) { chores in
            if let i = chores.firstIndex(where: { $0.id == chore.id }) {
                chores[i].isDone = done
                chores[i].completedBy = done ? by : nil
            }
        }
        persist { try await self.service.setCompletion(chore, done: done, occurrence: occurrence, by: by, in: household) }
    }

    func registerSubscriptions() async { await service.registerSubscriptions() }

    func assign(_ chore: SharedChore, to member: String?, in household: Household) {
        applyLocal(household.id) { chores in
            if let i = chores.firstIndex(where: { $0.id == chore.id }) { chores[i].assignee = member }
        }
        persist { try await self.service.assign(chore, to: member, in: household) }
    }

    func delete(_ chore: SharedChore, in household: Household) {
        applyLocal(household.id) { $0.removeAll { $0.id == chore.id } }
        persist { try await self.service.deleteChore(chore, in: household) }
    }

    func share(for household: Household) async -> (CKShare, CKContainer)? { try? await service.share(for: household) }

    /// Adds an app friend to a household by their CloudKit user record name.
    /// Returns nil on success, or an error message.
    func addFriend(_ profile: SharedProfile, to household: Household) async -> String? {
        guard let recordName = profile.cloudUserRecordName else {
            return String(localized: "\(profile.displayName) needs to update the app before they can be added this way.")
        }
        do {
            try await service.addFriend(userRecordName: recordName, to: household)
            await refreshQuietly()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

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
            households = fresh
        }
    }
}

struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

struct HouseholdsView: View {
    @Environment(SocialAccount.self) private var account
    @State private var model = HouseholdsModel()
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
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
