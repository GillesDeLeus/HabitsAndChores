import XCTest
@testable import HabitsAndChores

final class ModerationAndHandleTests: XCTestCase {

    func testContentModerationFlagsBlockedTerms() {
        XCTAssertTrue(ContentModeration.isAcceptable("morning_walk"))
        XCTAssertTrue(ContentModeration.isAcceptable("Alex"))
        XCTAssertFalse(ContentModeration.isAcceptable("shit"))
        XCTAssertFalse(ContentModeration.isAcceptable("shitty_handle"), "substring match")
        XCTAssertFalse(ContentModeration.isAcceptable("BITCH"), "case-insensitive")
    }

    func testNormalizedHandleValidation() {
        XCTAssertEqual(normalizedHandle("Bob"), "bob", "lowercased")
        XCTAssertEqual(normalizedHandle("  Valid_1 "), "valid_1", "trimmed")
        XCTAssertNil(normalizedHandle("ab"), "too short")
        XCTAssertNil(normalizedHandle(String(repeating: "a", count: 21)), "too long")
        XCTAssertNil(normalizedHandle("has space"))
        XCTAssertNil(normalizedHandle("emoji😀x"))
        XCTAssertNotNil(normalizedHandle("under_score9"))
    }
}
