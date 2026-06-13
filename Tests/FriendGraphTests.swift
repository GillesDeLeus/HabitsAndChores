import XCTest
@testable import HabitsAndChores

final class FriendGraphTests: XCTestCase {

    private let me = "me"

    private func edge(_ owner: String, _ other: String, _ state: FriendEdge.State = .active) -> FriendEdge {
        FriendEdge(owner: owner, other: other, state: state, createdAt: .now)
    }

    func testMutualActiveEdgesAreFriends() {
        let mine = [edge(me, "A")]
        let incoming = [edge("A", me)]
        let graph = FriendGraph(myEdges: mine, incoming: incoming)
        XCTAssertEqual(graph.friendIDs, ["A"])
        XCTAssertTrue(graph.incomingRequestIDs.isEmpty)
        XCTAssertTrue(graph.outgoingPendingIDs.isEmpty)
    }

    func testIncomingRequestWhenNoEdgeBack() {
        let graph = FriendGraph(myEdges: [], incoming: [edge("B", me)])
        XCTAssertEqual(graph.incomingRequestIDs, ["B"])
        XCTAssertTrue(graph.friendIDs.isEmpty)
    }

    func testOutgoingPendingWhenNoReciprocal() {
        let graph = FriendGraph(myEdges: [edge(me, "C")], incoming: [])
        XCTAssertEqual(graph.outgoingPendingIDs, ["C"])
        XCTAssertTrue(graph.friendIDs.isEmpty)
    }

    func testBlockedEdgeIsExcludedEverywhere() {
        // I blocked D, but D still has an active edge to me.
        let graph = FriendGraph(myEdges: [edge(me, "D", .blocked)], incoming: [edge("D", me)])
        XCTAssertFalse(graph.friendIDs.contains("D"))
        XCTAssertFalse(graph.incomingRequestIDs.contains("D"))   // I already have an edge to D
        XCTAssertFalse(graph.outgoingPendingIDs.contains("D"))   // my edge isn't active
    }

    func testMixedGraph() {
        let mine = [edge(me, "A"), edge(me, "C")]               // A mutual, C pending
        let incoming = [edge("A", me), edge("B", me)]           // A mutual, B incoming
        let graph = FriendGraph(myEdges: mine, incoming: incoming)
        XCTAssertEqual(Set(graph.friendIDs), ["A"])
        XCTAssertEqual(Set(graph.incomingRequestIDs), ["B"])
        XCTAssertEqual(Set(graph.outgoingPendingIDs), ["C"])
    }
}
