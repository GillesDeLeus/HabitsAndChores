import SwiftUI

/// Read-only view of another user's public profile, rendered from their
/// `SharedProfile` snapshot (the same shape the Awards tab shows for yourself).
struct ProfileDetailView: View {
    let profile: SharedProfile

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

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
