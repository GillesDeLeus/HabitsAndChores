import SwiftUI

/// Read-only view of another user's public profile, rendered from their
/// `SharedProfile` snapshot (the same shape the Awards tab shows for yourself).
struct ProfileDetailView: View {
    let profile: SharedProfile

    @Environment(SocialAccount.self) private var account
    @Environment(\.dismiss) private var dismiss
    private let service: SocialService = CloudKitSocialService()

    @State private var confirmBlock = false
    @State private var showReport = false
    @State private var notice: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

    private var canModerate: Bool {
        if let me = account.userID { return me != profile.userID }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                stats
                badges
            }
            .padding()
        }
        .navigationTitle("@\(profile.handle)")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if canModerate {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report…") { showReport = true }
                        Button("Block", role: .destructive) { confirmBlock = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Safety options")
                }
            }
        }
        .confirmationDialog("Block \(profile.displayName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { block() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They’ll be removed from your friends and hidden from your lists.")
        }
        .confirmationDialog("Report \(profile.displayName)", isPresented: $showReport, titleVisibility: .visible) {
            Button("Inappropriate profile") { report("Inappropriate profile") }
            Button("Harassment or abuse") { report("Harassment or abuse") }
            Button("Spam") { report("Spam") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your report is sent for review. You can also block this user.")
        }
        .alert("Thanks", isPresented: .constant(notice != nil), presenting: notice) { _ in
            Button("OK") { notice = nil; dismiss() }
        } message: { Text($0) }
    }

    private func block() {
        guard let me = account.userID else { return }
        Task {
            try? await service.upsertEdge(owner: me, other: profile.userID, state: .blocked)
            dismiss()
        }
    }

    private func report(_ reason: String) {
        guard let me = account.userID else { return }
        Task {
            try? await service.report(reporterID: me, reportedID: profile.userID, reason: reason)
            // Reporting also blocks, to protect the reporter immediately.
            try? await service.upsertEdge(owner: me, other: profile.userID, state: .blocked)
            notice = "Report submitted and the user has been blocked."
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            AvatarView(profile: profile, size: 72)
            Text(profile.displayName).font(.title2.bold())
            HStack {
                Text("Level \(profile.level)").font(.headline)
                Text("·").foregroundStyle(.secondary)
                Text(GamificationEngine.title(forLevel: profile.level))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Label("\(profile.points) points", systemImage: "star.circle.fill")
                .font(.subheadline.bold()).foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var stats: some View {
        HStack(spacing: 12) {
            stat("\(profile.bestCurrentStreak)", "current streak", "flame.fill", .orange)
            stat("\(profile.longestStreak)", "longest streak", "trophy.fill", .yellow)
        }
    }

    private func stat(_ value: String, _ caption: String, _ image: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: image).font(.title2).foregroundStyle(tint)
            Text(value).font(.title3.bold())
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Badges").font(.headline)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(GamificationEngine.achievements) { badge in
                    TierBadgeView(achievement: badge, tier: profile.badgeTiers[badge.id] ?? 0)
                }
            }
        }
    }
}
