import Foundation
import OSLog
import CloudKit

/// Keeps the public profile reasonably fresh by re-publishing the derived summary
/// (level, points, streaks, badge tiers) when the app becomes active or
/// backgrounds — throttled so it never spams CloudKit. No-op when anonymous.
@MainActor
enum ProfileSync {
    private static var lastPublish = Date.distantPast
    private static let minInterval: TimeInterval = 120

    static func republish(account: SocialAccount, tasks: [TaskItem],
                          shared: [GamificationEngine.SharedChoreStat] = [],
                          service: SocialService, force: Bool = false) async {
        guard account.isJoined, let me = account.userID, let handle = account.handle else { return }
        // Accounts created before cloudUserRecordName existed need a one-time backfill
        // (and a publish) so friends can add them to households.
        let needsBackfill = account.cloudUserRecordName == nil
        if !force, !needsBackfill, Date.now.timeIntervalSince(lastPublish) < minInterval { return }

        if needsBackfill,
           let recordName = try? await CKContainer(identifier: CloudKitSocialService.containerID)
               .userRecordID().recordName {
            account.updateCloudUserRecordName(recordName)
        }

        let summary = GamificationEngine.summary(for: tasks, shared: shared)
        let profile = SharedProfile(
            userID: me, handle: handle,
            displayName: account.displayName.isEmpty ? handle : account.displayName,
            summary: summary,
            avatarConfig: account.avatarConfig,
            photoData: account.photoData,
            cloudUserRecordName: account.cloudUserRecordName
        )
        do {
            try await service.publish(profile)
            lastPublish = .now
        } catch {
            Logger.social.error("profile republish failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
