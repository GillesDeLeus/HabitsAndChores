import XCTest
@testable import HabitsAndChores

@MainActor
final class FriendsModelTests: XCTestCase {

    private func makeModel(_ fake: FakeSocialService, me: String = "me") -> FriendsModel {
        FriendsModel(service: fake, me: me)
    }

    func testSendRequestShowsAsOutgoing() async {
        let fake = FakeSocialService()
        fake.seed(.stub("A"))
        let model = makeModel(fake)

        await model.sendRequest(to: .stub("A"))   // mutate + reload

        XCTAssertEqual(model.outgoing.map(\.userID), ["A"])
        XCTAssertTrue(model.friends.isEmpty)
        XCTAssertEqual(fake.edge("me", "A")?.state, .active)
    }

    func testAcceptIncomingBecomesFriend() async {
        let fake = FakeSocialService()
        fake.seed(.stub("B"))
        fake.seedEdge("B", "me", .active)         // incoming request
        let model = makeModel(fake)
        await model.reload()
        XCTAssertEqual(model.incoming.map(\.userID), ["B"])

        await model.accept(.stub("B"))

        XCTAssertEqual(model.friends.map(\.userID), ["B"])
        XCTAssertTrue(model.incoming.isEmpty)
    }

    func testBlockRemovesFromAllLists() async {
        let fake = FakeSocialService()
        fake.seed(.stub("C"))
        fake.seedEdge("me", "C", .active)
        fake.seedEdge("C", "me", .active)         // currently friends
        let model = makeModel(fake)
        await model.reload()
        XCTAssertEqual(model.friends.map(\.userID), ["C"])

        await model.block(.stub("C"))

        XCTAssertFalse(model.friends.contains { $0.userID == "C" })
        XCTAssertFalse(model.incoming.contains { $0.userID == "C" })
        XCTAssertFalse(model.outgoing.contains { $0.userID == "C" })
        XCTAssertEqual(fake.edge("me", "C")?.state, .blocked)
    }

    func testReportIsRecorded() async {
        let fake = FakeSocialService()
        let model = makeModel(fake)
        await model.report(.stub("X"), reason: "Spam")
        XCTAssertEqual(fake.reports.count, 1)
        XCTAssertEqual(fake.reports.first?.reported, "X")
        XCTAssertEqual(fake.reports.first?.reason, "Spam")
    }

    func testFriendOfFriendSuggestion() async {
        let fake = FakeSocialService()
        fake.seed(.stub("A")); fake.seed(.stub("C"))
        // me <-> A (mutual)
        fake.seedEdge("me", "A"); fake.seedEdge("A", "me")
        // A <-> C (mutual) — C is a friend-of-friend, not yet connected to me
        fake.seedEdge("A", "C"); fake.seedEdge("C", "A")
        let model = makeModel(fake)

        await model.reload()

        XCTAssertEqual(model.friends.map(\.userID), ["A"])
        let suggestion = model.suggestions.first { $0.profile.userID == "C" }
        XCTAssertNotNil(suggestion, "C should be suggested as a friend-of-friend")
        XCTAssertEqual(suggestion?.mutualCount, 1)
    }
}
