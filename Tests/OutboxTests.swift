import XCTest
@testable import HabitsAndChores

/// The offline outbox persists pending writes as JSON, so its correctness rests on
/// `ChoreDraft` and `HouseholdMutation` round-tripping through Codable intact.
final class OutboxTests: XCTestCase {

    func testChoreDraftCodableRoundTrip() throws {
        var draft = ChoreDraft()
        draft.title = "Bins"
        draft.isTodo = true
        draft.dueDate = Date(timeIntervalSince1970: 1000)
        draft.scheduledDate = Date(timeIntervalSince1970: 2000)
        draft.priority = .high
        draft.todoReminderMode = .dailyUntilDone
        draft.frequency = .weekly(on: [2, 4])
        draft.rotates = true
        draft.assignee = "Sam"

        let data = try JSONEncoder().encode(draft)
        let back = try JSONDecoder().decode(ChoreDraft.self, from: data)

        XCTAssertEqual(back.title, "Bins")
        XCTAssertTrue(back.isTodo)
        XCTAssertEqual(back.dueDate, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(back.scheduledDate, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(back.priority, .high)
        XCTAssertEqual(back.todoReminderMode, .dailyUntilDone)
        XCTAssertEqual(back.frequency, .weekly(on: [2, 4]))
        XCTAssertTrue(back.rotates)
        XCTAssertEqual(back.assignee, "Sam")
    }

    func testMutationQueueCodableRoundTrip() throws {
        let zone = ZoneRef(zoneName: "household-1", ownerName: "_owner", scopeRaw: 3) // 3 = shared
        var draft = ChoreDraft(); draft.title = "Dishes"
        let queue: [HouseholdMutation] = [
            .upsertChore(opID: "1", zone: zone, householdID: "root", recordName: "chore1", draft: draft),
            .deleteChore(opID: "2", zone: zone, recordName: "chore1"),
            .setCompletion(opID: "3", zone: zone, choreRecordName: "chore1",
                           occurrence: Date(timeIntervalSince1970: 0), by: "Sam", done: true, completionRecordName: "c1"),
            .assign(opID: "4", zone: zone, choreRecordName: "chore1", member: "Alex"),
        ]

        let data = try JSONEncoder().encode(queue)
        let back = try JSONDecoder().decode([HouseholdMutation].self, from: data)

        XCTAssertEqual(back.map(\.id), ["1", "2", "3", "4"])

        guard case let .upsertChore(_, z, householdID, recordName, decodedDraft) = back[0] else {
            return XCTFail("expected upsertChore")
        }
        XCTAssertEqual(z.zoneName, "household-1")
        XCTAssertEqual(z.scope, .shared)
        XCTAssertEqual(householdID, "root")
        XCTAssertEqual(recordName, "chore1")
        XCTAssertEqual(decodedDraft.title, "Dishes")

        guard case let .setCompletion(_, _, choreRecordName, _, by, done, completionRecordName) = back[2] else {
            return XCTFail("expected setCompletion")
        }
        XCTAssertEqual(choreRecordName, "chore1")
        XCTAssertEqual(by, "Sam")
        XCTAssertTrue(done)
        XCTAssertEqual(completionRecordName, "c1")

        guard case let .assign(_, _, _, member) = back[3] else { return XCTFail("expected assign") }
        XCTAssertEqual(member, "Alex")
    }
}
