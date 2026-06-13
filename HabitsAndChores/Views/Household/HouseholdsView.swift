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

    func reload() async {
        loading = true
        defer { loading = false }
        available = await service.isAvailable()
        guard available else { households = []; return }
        do {
            households = try await service.households()
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

    func addChore(to household: Household, title: String) async { await run { try await service.addChore(to: household, title: title) } }
    func setDone(_ chore: SharedChore, in household: Household, _ done: Bool) async { await run { try await service.setDone(chore, in: household, done: done) } }
    func assign(_ chore: SharedChore, to member: String?, in household: Household) async { await run { try await service.assign(chore, to: member, in: household) } }
    func delete(_ chore: SharedChore, in household: Household) async { await run { try await service.deleteChore(chore, in: household) } }
    func share(for household: Household) async -> (CKShare, CKContainer)? { try? await service.share(for: household) }

    /// Adds an app friend to a household by their CloudKit user record name.
    /// Returns nil on success, or an error message.
    func addFriend(_ profile: SharedProfile, to household: Household) async -> String? {
        guard let recordName = profile.cloudUserRecordName else {
            return String(localized: "\(profile.displayName) needs to update the app before they can be added this way.")
        }
        do {
            try await service.addFriend(userRecordName: recordName, to: household)
            await reload()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func run(_ work: () async throws -> Void) async {
        do { try await work(); await reload() }
        catch { self.error = error.localizedDescription }
    }
}

struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

struct HouseholdsView: View {
    @State private var model = HouseholdsModel()
    @State private var creating = false
    @State private var newName = ""
    @State private var sharePresentation: SharePresentation?

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
        .task { await model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .householdsChanged)) { _ in
            Task { await model.reload() }
        }
        .alert("New household", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("e.g. “Home” or “Flat 3B”. You can invite people next.")
        }
        .sheet(item: $sharePresentation) { presentation in
            HouseholdShareSheet(share: presentation.share, container: presentation.container)
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newName = ""
        Task {
            if let share = await model.create(name: name) {
                sharePresentation = SharePresentation(
                    share: share, container: CKContainer(identifier: HouseholdService.containerID))
            }
        }
    }
}
