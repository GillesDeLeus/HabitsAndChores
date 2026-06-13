import Foundation
import Observation

/// The opt-in gate for all social features. Defaults to `.anonymous`, in which
/// case nothing is ever written to the public CloudKit database and the app
/// behaves exactly as it does without an account. Local-only state, including a
/// cached copy of the user's chosen avatar so it can be shown and re-published.
@MainActor
@Observable
final class SocialAccount {
    enum State: Equatable {
        case anonymous
        case active(userID: String, handle: String)
    }

    private(set) var state: State = .anonymous
    private(set) var displayName: String = ""

    // Avatar (cached locally). A photo takes precedence over a built character.
    private(set) var avatarConfig: AvatarConfig?
    private(set) var photoData: Data?

    private let defaults: UserDefaults
    private enum Key {
        static let joined = "social.joined"
        static let handle = "social.handle"
        static let userID = "social.userID"
        static let displayName = "social.displayName"
        static let avatarConfig = "social.avatarConfig"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    var isJoined: Bool { if case .active = state { true } else { false } }
    var handle: String? { if case let .active(_, handle) = state { handle } else { nil } }
    var userID: String? { if case let .active(userID, _) = state { userID } else { nil } }

    func restore() {
        if defaults.bool(forKey: Key.joined),
           let id = defaults.string(forKey: Key.userID), !id.isEmpty,
           let h = defaults.string(forKey: Key.handle), !h.isEmpty {
            state = .active(userID: id, handle: h)
            displayName = defaults.string(forKey: Key.displayName) ?? h
            avatarConfig = AvatarConfig(data: defaults.data(forKey: Key.avatarConfig))
            photoData = try? Data(contentsOf: Self.photoURL)
        } else {
            state = .anonymous
        }
    }

    func markJoined(userID: String, handle: String, displayName: String) {
        defaults.set(true, forKey: Key.joined)
        defaults.set(userID, forKey: Key.userID)
        defaults.set(handle, forKey: Key.handle)
        defaults.set(displayName, forKey: Key.displayName)
        state = .active(userID: userID, handle: handle)
        self.displayName = displayName
    }

    func markLeft() {
        for key in [Key.joined, Key.userID, Key.handle, Key.displayName, Key.avatarConfig] {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: Self.photoURL)
        state = .anonymous
        displayName = ""
        avatarConfig = nil
        photoData = nil
    }

    // MARK: - Avatar

    func setCharacterAvatar(_ config: AvatarConfig) {
        avatarConfig = config
        defaults.set(config.encoded, forKey: Key.avatarConfig)
        photoData = nil
        try? FileManager.default.removeItem(at: Self.photoURL)
    }

    func setPhotoAvatar(_ data: Data) {
        try? FileManager.default.createDirectory(
            at: Self.photoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.photoURL)
        photoData = data
        avatarConfig = nil
        defaults.removeObject(forKey: Key.avatarConfig)
    }

    func clearAvatar() {
        avatarConfig = nil
        photoData = nil
        defaults.removeObject(forKey: Key.avatarConfig)
        try? FileManager.default.removeItem(at: Self.photoURL)
    }

    private static var photoURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("avatar.jpg")
    }
}
