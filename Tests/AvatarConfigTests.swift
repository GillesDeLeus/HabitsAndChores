import XCTest
@testable import HabitsAndChores

final class AvatarConfigTests: XCTestCase {

    func testCodableRoundTrip() {
        var config = AvatarConfig()
        config.hair = 3
        config.eyes = 2
        config.background = 7
        config.accessory = 1
        let decoded = AvatarConfig(data: config.encoded)
        XCTAssertEqual(decoded, config)
    }

    func testInitFromNilDataReturnsNil() {
        XCTAssertNil(AvatarConfig(data: nil))
    }

    func testRandomStaysWithinOptionRanges() {
        for _ in 0..<200 {
            let c = AvatarConfig.random()
            XCTAssertTrue((0..<AvatarConfig.backgroundCount).contains(c.background))
            XCTAssertTrue((0..<AvatarConfig.skinCount).contains(c.skin))
            XCTAssertTrue((0..<AvatarConfig.hairCount).contains(c.hair))
            XCTAssertTrue((0..<AvatarConfig.hairColorCount).contains(c.hairColor))
            XCTAssertTrue((0..<AvatarConfig.eyebrowsCount).contains(c.eyebrows))
            XCTAssertTrue((0..<AvatarConfig.eyesCount).contains(c.eyes))
            XCTAssertTrue((0..<AvatarConfig.mouthCount).contains(c.mouth))
            XCTAssertTrue((0..<AvatarConfig.facialHairCount).contains(c.facialHair))
            XCTAssertTrue((0..<AvatarConfig.accessoryCount).contains(c.accessory))
        }
    }
}
