import Foundation

/// A single directed relationship edge that the **owner** controls. CloudKit's
/// public database only lets a record's creator modify it, so we model mutual
/// friendship as two edges (A→B and B→A) — each user only ever writes their own.
/// A friendship is mutual when both directed edges are `.active`.
struct FriendEdge: Identifiable, Equatable {
    enum State: String { case active, declined, blocked }

    let owner: String
    let other: String
    var state: State
    var createdAt: Date

    var id: String { "\(owner)->\(other)" }
}

/// Derives friend / request / pending lists from the two sets of edges:
/// the ones I own (me→X) and the ones addressed to me (X→me).
struct FriendGraph {
    let myEdges: [FriendEdge]    // owner == me
    let incoming: [FriendEdge]   // other == me

    private func myEdge(to id: String) -> FriendEdge? { myEdges.first { $0.other == id } }

    /// Mutual: I have an active edge to them AND they have an active edge to me.
    var friendIDs: [String] {
        myEdges
            .filter { $0.state == .active }
            .map(\.other)
            .filter { other in incoming.contains { $0.owner == other && $0.state == .active } }
    }

    /// They sent me an active edge and I haven't responded yet.
    var incomingRequestIDs: [String] {
        incoming
            .filter { $0.state == .active }
            .map(\.owner)
            .filter { from in myEdge(to: from) == nil }
    }

    /// I sent an active edge and they haven't reciprocated yet.
    var outgoingPendingIDs: [String] {
        myEdges
            .filter { $0.state == .active }
            .map(\.other)
            .filter { to in !incoming.contains { $0.owner == to && $0.state == .active } }
    }
}
