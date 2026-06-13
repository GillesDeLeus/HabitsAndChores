import Foundation
import CloudKit
import OSLog

extension Notification.Name {
    /// Posted when a friend-graph push arrives, so open views can reload.
    static let friendGraphChanged = Notification.Name("friendGraphChanged")
}

/// Manages the CloudKit subscription that delivers a push whenever a `FriendEdge`
/// addressed to the signed-in user is created or updated — i.e. an incoming
/// friend request or an acceptance of one they sent.
@MainActor
enum SocialPushManager {
    private static var database: CKDatabase {
        CKContainer(identifier: CloudKitSocialService.containerID).publicCloudDatabase
    }

    private static func subscriptionID(for me: String) -> String { "friend-edges-\(me)" }
    private static func flagKey(for me: String) -> String { "social.subscribed.\(me)" }

    static func registerSubscription(for me: String) async {
        // Saving is cheap but we avoid redundant round-trips once it's known to exist.
        guard !UserDefaults.standard.bool(forKey: flagKey(for: me)) else { return }

        let predicate = NSPredicate(format: "other == %@", me)
        let subscription = CKQuerySubscription(
            recordType: "FriendEdge",
            predicate: predicate,
            subscriptionID: subscriptionID(for: me),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertBody = String(localized: "You have new friend activity in Habits & Chores.")
        info.soundName = "default"
        info.shouldBadge = true
        info.shouldSendContentAvailable = true   // also wake the app to refresh
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
            UserDefaults.standard.set(true, forKey: flagKey(for: me))
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already exists on the server — treat as success.
            UserDefaults.standard.set(true, forKey: flagKey(for: me))
        } catch {
            Logger.cloudkit.error("friend subscription registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func removeSubscription(for me: String) async {
        _ = try? await database.deleteSubscription(withID: subscriptionID(for: me))
        UserDefaults.standard.removeObject(forKey: flagKey(for: me))
    }
}
