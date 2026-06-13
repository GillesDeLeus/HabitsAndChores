import SwiftUI
import SwiftData

struct AwardsView: View {
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }, sort: \TaskItem.title)
    private var tasks: [TaskItem]

    @State private var confettiTrigger = 0
    @State private var summary = GamificationEngine.Summary()

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

    /// Cheap key that changes when tasks/completions change; drives recompute.
    private var statsKey: String {
        "\(tasks.count)-\(tasks.reduce(0) { $0 + $1.completions.count })"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    LevelCard(summary: summary)
                    StatTiles(summary: summary)
                    badgeSection(summary)
                }
                .padding()
            }
            .navigationTitle("Awards")
            .background(Color(.systemGroupedBackground))
            .overlay { ConfettiView(trigger: confettiTrigger) }
            .task(id: statsKey) {
                summary = GamificationEngine.summary(for: tasks)
                celebrateIfNeeded(summary)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { FriendsView() } label: {
                        Image(systemName: "person.2.fill")
                    }
                    .accessibilityLabel("Friends")
                }
            }
        }
    }

    private func badgeSection(_ s: GamificationEngine.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Badges").font(.headline)
                Spacer()
                Text("\(GamificationEngine.tiersEarned(in: s))/\(GamificationEngine.totalTiers) tiers")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(GamificationEngine.achievements) { badge in
                    TierBadgeView(achievement: badge,
                                  tier: badge.tierReached(s),
                                  value: badge.value(s))
                }
            }
        }
    }

    private func celebrateIfNeeded(_ s: GamificationEngine.Summary) {
        if AchievementTracker.registerAndCheck(s) {
            Haptics.celebrate()
            confettiTrigger += 1
        }
    }
}

// MARK: - Level card

private struct LevelCard: View {
    let summary: GamificationEngine.Summary

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(summary.level)").font(.title.bold())
                    Text(summary.levelTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label("\(summary.totalPoints)", systemImage: "star.circle.fill")
                        .font(.title3.bold()).foregroundStyle(.orange)
                    Text("points").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: summary.levelProgress) {
                HStack {
                    Text("\(summary.xpIntoLevel) / \(summary.xpForLevelSpan) XP")
                    Spacer()
                    if summary.pointsToNextLevel > 0 {
                        Text("\(summary.pointsToNextLevel) to level \(summary.level + 1)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .tint(.orange)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Stat tiles

private struct StatTiles: View {
    let summary: GamificationEngine.Summary

    var body: some View {
        HStack(spacing: 12) {
            WeeklyRingTile(progress: summary.weeklyProgress,
                           completed: summary.completedThisWeek,
                           total: summary.scheduledThisWeek)
            StatTile(value: "\(summary.bestCurrentStreak)", caption: "current streak",
                     systemImage: "flame.fill", tint: .orange)
            StatTile(value: "\(summary.longestStreak)", caption: "longest streak",
                     systemImage: "trophy.fill", tint: .yellow)
        }
    }
}

private struct StatTile: View {
    let value: String
    let caption: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(tint)
            Text(value).font(.title3.bold())
            Text(caption).font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct WeeklyRingTile: View {
    let progress: Double
    let completed: Int
    let total: Int

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))%").font(.caption.bold())
            }
            .frame(width: 44, height: 44)
            Text("\(completed)/\(total) this week")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    AwardsView()
        .modelContainer(PreviewData.container)
}
