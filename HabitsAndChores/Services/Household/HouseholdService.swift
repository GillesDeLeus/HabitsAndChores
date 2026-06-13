import Foundation
import CloudKit
import OSLog

extension Notification.Name {
    /// Posted when a household share is accepted or data changes.
    static let householdsChanged = Notification.Name("householdsChanged")
}

// MARK: - Models

/// A shared group (couple / household) backed by a CKShare on a custom zone.
struct Household: Identifiable {
    let id: String                  // root record name
    let name: String
    let zoneID: CKRecordZone.ID
    let scope: CKDatabase.Scope     // .private if I own it, .shared if shared with me
    let members: [String]           // display names of participants
    var chores: [SharedChore]

    var isOwner: Bool { scope == .private }
}

/// A chore that belongs to a household and can be assigned to a member.
struct SharedChore: Identifiable {
    let id: String                  // record name
    var title: String
    var isDone: Bool
    var assignee: String?           // member display name, or nil = unassigned
}

enum HouseholdError: LocalizedError {
    case notOwner, noShare, participantNotFound

    var errorDescription: String? {
        switch self {
        case .notOwner: return String(localized: "Only the household owner can add members.")
        case .noShare: return String(localized: "This household can't be shared.")
        case .participantNotFound: return String(localized: "That friend isn't reachable on iCloud yet.")
        }
    }
}

// MARK: - Service

/// Direct CloudKit implementation of household sharing. Households are root
/// records in per-household custom zones in the owner's private database; a
/// `CKShare` on the root makes the zone (and its chores) available to invited
/// participants in their shared database.
struct HouseholdService {
    static let containerID = "iCloud.com.beullens.homesuite.HabitsAndChores"
    private static let zonePrefix = "household-"

    private var container: CKContainer { CKContainer(identifier: Self.containerID) }
    private func database(_ scope: CKDatabase.Scope) -> CKDatabase {
        scope == .shared ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private enum RecordType {
        static let household = "Household"
        static let chore = "SharedChore"
    }

    func isAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: Create

    /// Creates a new household + its CKShare, returning the share so the caller can
    /// present the system invitation UI.
    func createHousehold(name: String) async throws -> CKShare {
        let zone = CKRecordZone(zoneName: Self.zonePrefix + UUID().uuidString)
        _ = try await database(.private).save(zone)

        let root = CKRecord(recordType: RecordType.household,
                            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID))
        root["name"] = name
        root["createdAt"] = Date()

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = name as CKRecordValue
        share.publicPermission = .none

        let result = try await database(.private).modifyRecords(saving: [root, share], deleting: [])
        for (_, saveResult) in result.saveResults {
            if case .failure(let error) = saveResult { throw error }
        }
        return share
    }

    // MARK: Fetch

    func households() async throws -> [Household] {
        var result: [Household] = []
        for scope in [CKDatabase.Scope.private, .shared] {
            let db = database(scope)
            guard let zones = try? await db.allRecordZones() else { continue }
            for zone in zones where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
                guard let records = try? await allRecords(in: zone.zoneID, db: db),
                      let root = records.first(where: { $0.recordType == RecordType.household }) else { continue }
                let name = root["name"] as? String ?? "Household"

                let share = records.compactMap { $0 as? CKShare }.first
                let members = share.map { memberNames(of: $0) } ?? []

                let chores = records
                    .filter { $0.recordType == RecordType.chore }
                    .map { rec in
                        SharedChore(id: rec.recordID.recordName,
                                    title: rec["title"] as? String ?? "",
                                    isDone: (rec["isDone"] as? Int ?? 0) == 1,
                                    assignee: rec["assignee"] as? String)
                    }
                    .sorted { $0.title < $1.title }

                result.append(Household(id: root.recordID.recordName, name: name,
                                        zoneID: zone.zoneID, scope: scope,
                                        members: members, chores: chores))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    // MARK: Chores

    func addChore(to household: Household, title: String) async throws {
        let db = database(household.scope)
        let record = CKRecord(recordType: RecordType.chore,
                              recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: household.zoneID))
        record["title"] = title
        record["isDone"] = 0
        // Parent link so the chore is shared together with the household root.
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        record.parent = CKRecord.Reference(recordID: rootID, action: .none)
        record["household"] = CKRecord.Reference(recordID: rootID, action: .deleteSelf)
        _ = try await db.save(record)
    }

    func setDone(_ chore: SharedChore, in household: Household, done: Bool) async throws {
        try await update(chore, in: household) { $0["isDone"] = done ? 1 : 0 }
    }

    func assign(_ chore: SharedChore, to member: String?, in household: Household) async throws {
        try await update(chore, in: household) { $0["assignee"] = member }
    }

    func deleteChore(_ chore: SharedChore, in household: Household) async throws {
        let id = CKRecord.ID(recordName: chore.id, zoneID: household.zoneID)
        _ = try await database(household.scope).deleteRecord(withID: id)
    }

    /// Adds an existing app friend (by their CloudKit user record name) to a
    /// household as a read-write member, without a manual invite link. The invitee
    /// must still accept per CloudKit's rules. Owner only.
    func addFriend(userRecordName: String, to household: Household) async throws {
        guard household.scope == .private else { throw HouseholdError.notOwner }
        let db = database(.private)
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        let root = try await db.record(for: rootID)
        guard let shareRef = root.share,
              let share = try await db.record(for: shareRef.recordID) as? CKShare else {
            throw HouseholdError.noShare
        }
        let participant = try await fetchParticipant(userRecordName: userRecordName)
        participant.permission = .readWrite
        share.addParticipant(participant)
        let result = try await db.modifyRecords(saving: [share], deleting: [])
        for (_, saveResult) in result.saveResults {
            if case .failure(let error) = saveResult { throw error }
        }
    }

    private func fetchParticipant(userRecordName: String) async throws -> CKShare.Participant {
        let lookup = CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: userRecordName))
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookup])
            var participant: CKShare.Participant?
            operation.perShareParticipantResultBlock = { _, result in
                if case .success(let found) = result { participant = found }
            }
            operation.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    if let participant { continuation.resume(returning: participant) }
                    else { continuation.resume(throwing: HouseholdError.participantNotFound) }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    /// The CKShare for a household, for presenting the invitation UI (owner only).
    func share(for household: Household) async throws -> (CKShare, CKContainer)? {
        let db = database(household.scope)
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        guard let root = try? await db.record(for: rootID),
              let shareRef = root.share,
              let share = try? await db.record(for: shareRef.recordID) as? CKShare else { return nil }
        return (share, container)
    }

    // MARK: - Helpers

    private func update(_ chore: SharedChore, in household: Household,
                        _ mutate: (CKRecord) -> Void) async throws {
        let db = database(household.scope)
        let id = CKRecord.ID(recordName: chore.id, zoneID: household.zoneID)
        let record = try await db.record(for: id)
        mutate(record)
        _ = try await db.save(record)
    }

    /// Fetches every record in a zone via zone changes — works in custom/shared
    /// zones without the queryable indexes that `CKQuery` would require.
    private func allRecords(in zoneID: CKRecordZone.ID, db: CKDatabase) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config])
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { records.append(record) }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: records)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            db.add(operation)
        }
    }

    private func memberNames(of share: CKShare) -> [String] {
        let formatter = PersonNameComponentsFormatter()
        return share.participants.compactMap { participant in
            if let components = participant.userIdentity.nameComponents {
                let name = formatter.string(from: components)
                if !name.isEmpty { return name }
            }
            return participant.role == .owner ? String(localized: "Owner") : nil
        }
    }
}
