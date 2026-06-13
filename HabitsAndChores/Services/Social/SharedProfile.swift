import Foundation

/// The public, shareable projection of a user's progress. This is what other
/// users can read — a derived snapshot of `GamificationEngine.Summary`, never the
/// raw completion history. Lives in the public CloudKit database.
struct SharedProfile: Identifiable, Equatable {
    let userID: String          // stable identity (Sign in with Apple user id)
    var id: String { userID }
    var handle: String          // unique, lowercased lookup key
    var displayName: String
    var level: Int
    var points: Int
    var longestStreak: Int
    var bestCurrentStreak: Int
    var badgeTiers: [String: Int]   // achievement.id -> tier reached
    var updatedAt: Date

    // Avatar — a photo takes precedence; otherwise a built character; otherwise initials.
    var avatarConfig: AvatarConfig?
    var photoData: Data?

    init(userID: String, handle: String, displayName: String,
         level: Int, points: Int, longestStreak: Int, bestCurrentStreak: Int,
         badgeTiers: [String: Int], updatedAt: Date = .now,
         avatarConfig: AvatarConfig? = nil, photoData: Data? = nil) {
        self.userID = userID
        self.handle = handle
        self.displayName = displayName
        self.level = level
        self.points = points
        self.longestStreak = longestStreak
        self.bestCurrentStreak = bestCurrentStreak
        self.badgeTiers = badgeTiers
        self.updatedAt = updatedAt
        self.avatarConfig = avatarConfig
        self.photoData = photoData
    }
}

extension SharedProfile {
    /// Builds the public snapshot from the values `GamificationEngine` already computes.
    @MainActor
    init(userID: String, handle: String, displayName: String,
         summary: GamificationEngine.Summary,
         avatarConfig: AvatarConfig? = nil, photoData: Data? = nil) {
        self.init(
            userID: userID,
            handle: handle,
            displayName: displayName,
            level: summary.level,
            points: summary.totalPoints,
            longestStreak: summary.longestStreak,
            bestCurrentStreak: summary.bestCurrentStreak,
            badgeTiers: Dictionary(uniqueKeysWithValues:
                GamificationEngine.achievements.map { ($0.id, $0.tierReached(summary)) }),
            updatedAt: .now,
            avatarConfig: avatarConfig,
            photoData: photoData
        )
    }
}
