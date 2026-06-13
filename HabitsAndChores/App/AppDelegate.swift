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

    /// A CloudKit subscription fired (friend graph or household). Tell open views to reload.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        NotificationCenter.default.post(name: .friendGraphChanged, object: nil)
        NotificationCenter.default.post(name: .householdsChanged, object: nil)
        return .newData
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.cloudkit.error("remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // SwiftUI apps deliver CloudKit share acceptance to the *scene* delegate, so
    // route new scenes through SceneDelegate (which handles the accept).
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Accepts CloudKit household share invitations. SwiftUI manages the window; this
/// only adds scene-level share handling.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        let operation = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])
        operation.acceptSharesResultBlock = { result in
            if case .failure(let error) = result {
                Logger.cloudkit.error("accept share failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in NotificationCenter.default.post(name: .householdsChanged, object: nil) }
        }
        CKContainer(identifier: HouseholdService.containerID).add(operation)
    }
}
