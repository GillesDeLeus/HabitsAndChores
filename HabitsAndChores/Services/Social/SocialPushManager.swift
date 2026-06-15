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
        // Incoming friend requests / acceptances (FriendEdge addressed to me).
        await save(
            subscription: CKQuerySubscription(
                recordType: "FriendEdge",
                predicate: NSPredicate(format: "other == %@", me),
                subscriptionID: subscriptionID(for: me),
                options: [.firesOnRecordCreation, .firesOnRecordUpdate]),
            alert: String(localized: "You have new friend activity in Habits & Chores."),
            flagKey: flagKey(for: me),
            label: "friend")

        // Incoming household invitations (HouseholdInvite addressed to me).
        await save(
            subscription: CKQuerySubscription(
                recordType: "HouseholdInvite",
                predicate: NSPredicate(format: "invitee == %@", me),
                subscriptionID: "household-invites-\(me)",
                options: [.firesOnRecordCreation]),
            alert: String(localized: "You’ve been invited to a household in Habits & Chores."),
            flagKey: "household.invite.subscribed.\(me)",
            label: "household-invite")
    }

    /// Saves a query subscription once, guarded by a UserDefaults flag.
    private static func save(subscription: CKQuerySubscription, alert: String,
                             flagKey: String, label: String) async {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        let info = CKSubscription.NotificationInfo()
        info.alertBody = alert
        info.soundName = "default"
        info.shouldBadge = true
        info.shouldSendContentAvailable = true   // also wake the app to refresh
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            UserDefaults.standard.set(true, forKey: flagKey)   // already exists
        } catch {
            Logger.cloudkit.error("\(label, privacy: .public) subscription registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func removeSubscription(for me: String) async {
        _ = try? await database.deleteSubscription(withID: subscriptionID(for: me))
        _ = try? await database.deleteSubscription(withID: "household-invites-\(me)")
        UserDefaults.standard.removeObject(forKey: flagKey(for: me))
        UserDefaults.standard.removeObject(forKey: "household.invite.subscribed.\(me)")
    }
}
