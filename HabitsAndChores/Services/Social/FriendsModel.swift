import Foundation
import Observation

/// Loads and mutates the signed-in user's friend graph through a `SocialService`,
/// and computes friend-of-friend suggestions.
@MainActor
@Observable
final class FriendsModel {
    private let service: SocialService
    private let me: String

    struct Suggestion: Identifiable {
        let profile: SharedProfile
        let mutualCount: Int
        var id: String { profile.userID }
    }

    /// My relationship to a given user, used to pick the right action in the UI.
    enum Relationship { case none, isMe, friend, incoming, outgoing }

    var friends: [SharedProfile] = []
    var incoming: [SharedProfile] = []     // requests received (action needed)
    var outgoing: [SharedProfile] = []     // requests sent (waiting)
    var suggestions: [Suggestion] = []
    var loading = false
    var loadingSuggestions = false
    var error: String?

    private var friendIDs: Set<String> = []
    private var incomingIDs: Set<String> = []
    private var outgoingIDs: Set<String> = []
    private var myEdgeTargets: Set<String> = []   // everyone I have any edge to

    init(service: SocialService, me: String) {
        self.service = service
        self.me = me
    }

    func reload() async {
        loading = true
        do {
            let mine = try await service.edges(ownedBy: me)
            let toMe = try await service.edges(addressedTo: me)
            myEdgeTargets = Set(mine.map(\.other))
            let graph = FriendGraph(myEdges: mine, incoming: toMe)
            friendIDs = Set(graph.friendIDs)
            incomingIDs = Set(graph.incomingRequestIDs)
            outgoingIDs = Set(graph.outgoingPendingIDs)
            friends = try await service.profiles(userIDs: graph.friendIDs)
            incoming = try await service.profiles(userIDs: graph.incomingRequestIDs)
            outgoing = try await service.profiles(userIDs: graph.outgoingPendingIDs)
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        await loadSuggestions()
    }

    /// My relationship to `userID`, for choosing the right button on a profile.
    func relationship(to userID: String) -> Relationship {
        if userID == me { return .isMe }
        if friendIDs.contains(userID) { return .friend }
        if incomingIDs.contains(userID) { return .incoming }
        if outgoingIDs.contains(userID) { return .outgoing }
        return .none
    }

    /// Friends-of-friends, ranked by how many of my friends know them. Mutual on
    /// the friend's side is required (active edges both directions).
    private func loadSuggestions() async {
        loadingSuggestions = true
        defer { loadingSuggestions = false }

        let excluded = friendIDs.union([me]).union(incomingIDs).union(myEdgeTargets)
        var counts: [String: Int] = [:]
        for friend in friends.prefix(15) {
            guard let out = try? await service.edges(ownedBy: friend.userID),
                  let inc = try? await service.edges(addressedTo: friend.userID) else { continue }
            let theirOut = Set(out.filter { $0.state == .active }.map(\.other))
            let theirIn = Set(inc.filter { $0.state == .active }.map(\.owner))
            for candidate in theirOut.intersection(theirIn) where !excluded.contains(candidate) {
                counts[candidate, default: 0] += 1
            }
        }
        let topIDs = counts.sorted { $0.value > $1.value }.prefix(12).map(\.key)
        let profiles = (try? await service.profiles(userIDs: topIDs)) ?? []
        suggestions = profiles
            .map { Suggestion(profile: $0, mutualCount: counts[$0.userID] ?? 0) }
            .sorted { $0.mutualCount > $1.mutualCount }
    }

    func findProfile(handle: String) async -> SharedProfile? {
        try? await service.findProfile(handle: handle)
    }

    func sendRequest(to profile: SharedProfile) async {
        await mutate { try await service.upsertEdge(owner: me, other: profile.userID, state: .active) }
    }

    func accept(_ profile: SharedProfile) async {
        await mutate { try await service.upsertEdge(owner: me, other: profile.userID, state: .active) }
    }

    func decline(_ profile: SharedProfile) async {
        await mutate { try await service.upsertEdge(owner: me, other: profile.userID, state: .declined) }
    }

    /// Cancel an outgoing request or unfriend — just delete my own edge.
    func remove(_ profile: SharedProfile) async {
        await mutate { try await service.removeEdge(owner: me, other: profile.userID) }
    }

    private func mutate(_ work: () async throws -> Void) async {
        do {
            try await work()
            await reload()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
