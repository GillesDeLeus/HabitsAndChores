import Foundation

/// Abstraction over the social backend so the app depends on this, not on
/// CloudKit directly. Phase 1 covers account/profile; the friend graph is added
/// in a later phase by extending this protocol.
protocol SocialService {
    /// Whether the device has a usable iCloud account (required to write).
    func isAvailable() async -> Bool

    /// Reserves `handle` for `userID`. Throws `.handleTaken` if already claimed by
    /// someone else. Idempotent if the caller already owns it.
    func claimHandle(_ handle: String, for userID: String) async throws

    /// Creates or updates the caller's public profile.
    func publish(_ profile: SharedProfile) async throws

    /// Fetches a profile by user id, or nil if none exists.
    func profile(userID: String) async throws -> SharedProfile?

    /// Removes the caller's public profile and releases their handle.
    func deleteAccount(userID: String, handle: String) async throws

    // MARK: - Friend graph

    /// Looks up a profile by handle (for "add friend by handle").
    func findProfile(handle: String) async throws -> SharedProfile?

    /// Creates or updates the caller's own directed edge to `other`.
    func upsertEdge(owner: String, other: String, state: FriendEdge.State) async throws

    /// Deletes the caller's own directed edge to `other`.
    func removeEdge(owner: String, other: String) async throws

    /// All edges the user owns (me → others).
    func edges(ownedBy userID: String) async throws -> [FriendEdge]

    /// All edges addressed to the user (others → me).
    func edges(addressedTo userID: String) async throws -> [FriendEdge]

    /// Fetches profiles for a set of user ids (missing ones are skipped).
    func profiles(userIDs: [String]) async throws -> [SharedProfile]
}

enum SocialError: LocalizedError {
    case iCloudUnavailable
    case handleTaken
    case invalidHandle

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return String(localized: "iCloud is unavailable. Sign in to iCloud in Settings to use social features.")
        case .handleTaken:
            return String(localized: "That handle is already taken. Try another.")
        case .invalidHandle:
            return String(localized: "Handles must be 3–20 characters: letters, numbers, or underscore.")
        }
    }
}

/// Validates and normalizes a handle. Returns the lowercased canonical form, or
/// nil if invalid (3–20 chars of [a-z0-9_]).
func normalizedHandle(_ raw: String) -> String? {
    let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
    guard (3...20).contains(lower.count),
          lower.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    return lower
}
