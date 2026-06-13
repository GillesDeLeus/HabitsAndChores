import SwiftUI

/// A single tiered badge cell, reused on the Awards tab (own progress, `value`
/// supplied) and on a friend's profile (tier only, `value` nil).
struct TierBadgeView: View {
    let achievement: GamificationEngine.Achievement
    let tier: Int
    /// Current raw metric value, if known (own profile). Drives the progress line.
    var value: Int? = nil

    private var earned: Bool { tier > 0 }

    /// Bronze → Silver → Gold → Platinum → Diamond as tiers climb.
    private static let tierColors: [Color] = [
        Color(red: 0.80, green: 0.50, blue: 0.20),
        Color(red: 0.66, green: 0.66, blue: 0.70),
        Color(red: 0.95, green: 0.74, blue: 0.20),
        Color(red: 0.40, green: 0.78, blue: 0.78),
        Color(red: 0.60, green: 0.45, blue: 0.90),
    ]

    private var tierColor: Color {
        guard earned else { return .gray.opacity(0.3) }
        return Self.tierColors[min(tier - 1, Self.tierColors.count - 1)]
    }

    private var nextGoal: Int? {
        tier < achievement.tiers.count ? achievement.tiers[tier] : nil
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(tierColor.gradient).frame(width: 60, height: 60)
                Image(systemName: earned ? achievement.systemImage : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(earned ? .white : .secondary)
                if earned {
                    Text("\(tier)")
                        .font(.caption2.bold())
                        .foregroundStyle(tierColor)
                        .frame(width: 18, height: 18)
                        .background(.background, in: Circle())
                        .offset(x: 22, y: 22)
                }
            }
            Text(achievement.name)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(earned ? .primary : .secondary)

            HStack(spacing: 3) {
                ForEach(achievement.tiers.indices, id: \.self) { i in
                    Circle()
                        .fill(i < tier ? tierColor : Color.gray.opacity(0.3))
                        .frame(width: 5, height: 5)
                }
            }

            Group {
                if let value {
                    if let goal = nextGoal {
                        Text("\(value)/\(goal) \(achievement.unit)")
                    } else {
                        Text("Maxed! \(value) \(achievement.unit)")
                    }
                } else {
                    Text(earned ? "Tier \(tier)" : "Locked")
                }
            }
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(earned ? 1 : 0.75)
    }
}
