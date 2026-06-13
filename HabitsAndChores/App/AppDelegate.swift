import UIKit
import UserNotifications
import OSLog
import CloudKit

/// Handles remote-notification registration and delivery for CloudKit friend-graph
/// subscriptions. Attached to the SwiftUI app via `@UIApplicationDelegateAdaptor`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    /// A friend-graph subscription fired. Tell open views to reload.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        NotificationCenter.default.post(name: .friendGraphChanged, object: nil)
        return .newData
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.cloudkit.error("remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Accepts a household share when the user opens an invitation link.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        let container = CKContainer(identifier: HouseholdService.containerID)
        container.accept(metadata) { _, error in
            if let error {
                Logger.cloudkit.error("failed to accept share: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in NotificationCenter.default.post(name: .householdsChanged, object: nil) }
        }
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
