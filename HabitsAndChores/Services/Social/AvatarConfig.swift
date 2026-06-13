import Foundation

/// A composable cartoon avatar described purely by integer choices into the
/// palettes/part-sets defined in `CharacterAvatarView`. Codable and tiny, so it
/// syncs as one small JSON field on the public profile.
struct AvatarConfig: Codable, Equatable {
    var background = 0
    var skin = 2
    var hair = 1
    var hairColor = 0
    var eyebrows = 1
    var eyes = 0
    var mouth = 0
    var facialHair = 0
    var accessory = 0

    // Number of options available for each feature (used by the builder UI and
    // mirrored by the palettes/switches in CharacterAvatarView).
    static let backgroundCount = 12
    static let skinCount = 7
    static let hairCount = 8         // 0 == bald
    static let hairColorCount = 8
    static let eyebrowsCount = 4     // 0 == none
    static let eyesCount = 5
    static let mouthCount = 5
    static let facialHairCount = 5   // 0 == none
    static let accessoryCount = 5    // 0 == none

    static func random() -> AvatarConfig {
        AvatarConfig(
            background: .random(in: 0..<backgroundCount),
            skin: .random(in: 0..<skinCount),
            hair: .random(in: 0..<hairCount),
            hairColor: .random(in: 0..<hairColorCount),
            eyebrows: .random(in: 0..<eyebrowsCount),
            eyes: .random(in: 0..<eyesCount),
            mouth: .random(in: 0..<mouthCount),
            facialHair: .random(in: 0..<facialHairCount),
            accessory: .random(in: 0..<accessoryCount)
        )
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}

extension AvatarConfig {
    init?(data: Data?) {
        guard let data, let config = try? JSONDecoder().decode(AvatarConfig.self, from: data) else { return nil }
        self = config
    }
}
