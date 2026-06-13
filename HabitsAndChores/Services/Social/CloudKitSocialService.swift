import Foundation
import CloudKit

/// CloudKit-backed social service. Profiles and handle reservations live in the
/// public database of the app's container, so any signed-in user can read them
/// while only the owner can modify their own records.
struct CloudKitSocialService: SocialService {
    static let containerID = "iCloud.com.beullens.homesuite.HabitsAndChores"

    private var database: CKDatabase {
        CKContainer(identifier: Self.containerID).publicCloudDatabase
    }

    private enum RecordType {
        static let profile = "Profile"
        static let handle = "Handle"
        static let edge = "FriendEdge"
    }

    private func profileRecordID(_ userID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile_\(userID)")
    }
    private func handleRecordID(_ handle: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "handle_\(handle)")
    }
    private func edgeRecordID(owner: String, other: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "edge_\(owner)_\(other)")
    }

    // MARK: - SocialService

    func isAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: Self.containerID).accountStatus()
        return status == .available
    }

    func claimHandle(_ handle: String, for userID: String) async throws {
        let recordID = handleRecordID(handle)
        // If the handle record already exists and belongs to someone else, reject.
        if let existing = try? await database.record(for: recordID) {
            if existing["userID"] as? String == userID { return } // already ours
            throw SocialError.handleTaken
        }
        let record = CKRecord(recordType: RecordType.handle, recordID: recordID)
        record["userID"] = userID
        record["handle"] = handle
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Lost a race to claim it.
            throw SocialError.handleTaken
        }
    }

    func publish(_ profile: SharedProfile) async throws {
        let recordID = profileRecordID(profile.userID)
        // Upsert: start from the server record if present so we update in place.
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: RecordType.profile, recordID: recordID)
        record["userID"] = profile.userID
        record["handle"] = profile.handle
        record["displayName"] = profile.displayName
        record["level"] = profile.level
        record["points"] = profile.points
        record["longestStreak"] = profile.longestStreak
        record["bestCurrentStreak"] = profile.bestCurrentStreak
        record["badgeTiers"] = try? JSONEncoder().encode(profile.badgeTiers)
        record["updatedAt"] = profile.updatedAt
        record["avatarConfig"] = profile.avatarConfig?.encoded
        if let data = profile.photoData {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            try data.write(to: url)
            record["photo"] = CKAsset(fileURL: url)
        } else {
            record["photo"] = nil
        }
        _ = try await database.save(record)
    }

    func profile(userID: String) async throws -> SharedProfile? {
        guard let record = try? await database.record(for: profileRecordID(userID)) else { return nil }
        return Self.profile(from: record)
    }

    func deleteAccount(userID: String, handle: String) async throws {
        _ = try? await database.deleteRecord(withID: profileRecordID(userID))
        _ = try? await database.deleteRecord(withID: handleRecordID(handle))
    }

    // MARK: - Friend graph

    func findProfile(handle: String) async throws -> SharedProfile? {
        guard let canonical = normalizedHandle(handle),
              let handleRecord = try? await database.record(for: handleRecordID(canonical)),
              let userID = handleRecord["userID"] as? String else { return nil }
        return try await profile(userID: userID)
    }

    func upsertEdge(owner: String, other: String, state: FriendEdge.State) async throws {
        let recordID = edgeRecordID(owner: owner, other: other)
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: RecordType.edge, recordID: recordID)
        record["owner"] = owner
        record["other"] = other
        record["state"] = state.rawValue
        if record["createdAt"] == nil { record["createdAt"] = Date() }
        _ = try await database.save(record)
    }

    func removeEdge(owner: String, other: String) async throws {
        _ = try? await database.deleteRecord(withID: edgeRecordID(owner: owner, other: other))
    }

    func edges(ownedBy userID: String) async throws -> [FriendEdge] {
        try await queryEdges(NSPredicate(format: "owner == %@", userID))
    }

    func edges(addressedTo userID: String) async throws -> [FriendEdge] {
        try await queryEdges(NSPredicate(format: "other == %@", userID))
    }

    func profiles(userIDs: [String]) async throws -> [SharedProfile] {
        var result: [SharedProfile] = []
        for id in userIDs {
            if let profile = try? await profile(userID: id) { result.append(profile) }
        }
        return result
    }

    private func queryEdges(_ predicate: NSPredicate) async throws -> [FriendEdge] {
        let query = CKQuery(recordType: RecordType.edge, predicate: predicate)
        do {
            let (matches, _) = try await database.records(matching: query)
            return matches.compactMap { _, result in
                (try? result.get()).flatMap(Self.edge(from:))
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Record type not created yet (no edges exist) — treat as empty.
            return []
        }
    }

    // MARK: - Mapping

    static func edge(from record: CKRecord) -> FriendEdge? {
        guard let owner = record["owner"] as? String,
              let other = record["other"] as? String else { return nil }
        let state = FriendEdge.State(rawValue: record["state"] as? String ?? "active") ?? .active
        return FriendEdge(owner: owner, other: other, state: state,
                          createdAt: record["createdAt"] as? Date ?? .now)
    }

    static func profile(from record: CKRecord) -> SharedProfile? {
        guard let userID = record["userID"] as? String,
              let handle = record["handle"] as? String else { return nil }
        let tiers = (record["badgeTiers"] as? Data)
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        var photoData: Data?
        if let asset = record["photo"] as? CKAsset, let url = asset.fileURL {
            photoData = try? Data(contentsOf: url)
        }
        return SharedProfile(
            userID: userID,
            handle: handle,
            displayName: record["displayName"] as? String ?? handle,
            level: record["level"] as? Int ?? 1,
            points: record["points"] as? Int ?? 0,
            longestStreak: record["longestStreak"] as? Int ?? 0,
            bestCurrentStreak: record["bestCurrentStreak"] as? Int ?? 0,
            badgeTiers: tiers,
            updatedAt: record["updatedAt"] as? Date ?? .now,
            avatarConfig: AvatarConfig(data: record["avatarConfig"] as? Data),
            photoData: photoData
        )
    }
}
