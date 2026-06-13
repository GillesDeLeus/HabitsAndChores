import Foundation
@testable import HabitsAndChores

/// In-memory `SocialService` for testing `FriendsModel` and related logic without
/// touching CloudKit.
final class FakeSocialService: SocialService {
    var profiles: [String: SharedProfile] = [:]
    private var edgeStore: [String: FriendEdge] = [:]   // keyed "owner->other"
    private(set) var reports: [(reporter: String, reported: String, reason: String)] = []

    private func key(_ owner: String, _ other: String) -> String { "\(owner)->\(other)" }

    // MARK: Seeding helpers

    func seed(_ profile: SharedProfile) { profiles[profile.userID] = profile }

    func seedEdge(_ owner: String, _ other: String, _ state: FriendEdge.State = .active) {
        edgeStore[key(owner, other)] = FriendEdge(owner: owner, other: other, state: state, createdAt: .now)
    }

    func edge(_ owner: String, _ other: String) -> FriendEdge? { edgeStore[key(owner, other)] }

    // MARK: SocialService

    func isAvailable() async -> Bool { true }
    func claimHandle(_ handle: String, for userID: String) async throws {}
    func publish(_ profile: SharedProfile) async throws { profiles[profile.userID] = profile }
    func profile(userID: String) async throws -> SharedProfile? { profiles[userID] }

    func deleteAccount(userID: String, handle: String) async throws {
        profiles[userID] = nil
        edgeStore = edgeStore.filter { $0.value.owner != userID }
    }

    func findProfile(handle: String) async throws -> SharedProfile? {
        profiles.values.first { $0.handle == handle.lowercased() }
    }

    func upsertEdge(owner: String, other: String, state: FriendEdge.State) async throws {
        edgeStore[key(owner, other)] = FriendEdge(owner: owner, other: other, state: state, createdAt: .now)
    }

    func removeEdge(owner: String, other: String) async throws {
        edgeStore[key(owner, other)] = nil
    }

    func edges(ownedBy userID: String) async throws -> [FriendEdge] {
        edgeStore.values.filter { $0.owner == userID }
    }

    func edges(addressedTo userID: String) async throws -> [FriendEdge] {
        edgeStore.values.filter { $0.other == userID }
    }

    func edges(ownedByAny userIDs: [String]) async throws -> [FriendEdge] {
        let set = Set(userIDs)
        return edgeStore.values.filter { set.contains($0.owner) }
    }

    func edges(addressedToAny userIDs: [String]) async throws -> [FriendEdge] {
        let set = Set(userIDs)
        return edgeStore.values.filter { set.contains($0.other) }
    }

    func profiles(userIDs: [String]) async throws -> [SharedProfile] {
        userIDs.compactMap { profiles[$0] }
    }

    func report(reporterID: String, reportedID: String, reason: String) async throws {
        reports.append((reporterID, reportedID, reason))
    }
}

extension SharedProfile {
    /// Minimal profile for tests.
    static func stub(_ userID: String, handle: String? = nil) -> SharedProfile {
        SharedProfile(userID: userID, handle: handle ?? userID, displayName: handle ?? userID,
                      level: 1, points: 0, longestStreak: 0, bestCurrentStreak: 0, badgeTiers: [:])
    }
}
