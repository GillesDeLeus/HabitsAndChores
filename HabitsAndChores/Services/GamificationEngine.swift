import Foundation

/// Derives all gamification values (points, levels, streaks, weekly goal, badges)
/// from the existing `TaskItem` / `Completion` data. Nothing here is persisted —
/// it is recomputed on demand, so it needs no schema change and stays in sync
/// with whatever the user has actually done.
@MainActor
enum GamificationEngine {

    /// Points awarded per completed (done) occurrence. Skips and misses give none.
    static let pointsPerCompletion = 10

    // MARK: - Summary

    struct Summary {
        var totalCompleted = 0
        var totalPoints = 0

        var level = 1
        var levelTitle = ""
        var xpIntoLevel = 0          // points earned since reaching `level`
        var xpForLevelSpan = 100     // points between `level` and `level + 1`
        var pointsToNextLevel = 100
        var levelProgress: Double = 0

        var longestStreak = 0
        var bestCurrentStreak = 0

        var completedThisWeek = 0
        var scheduledThisWeek = 0
        var weeklyProgress: Double = 0

        var choreCompleted = 0
        var habitCompleted = 0
        var distinctCategories = 0
        var perfectWeekCount = 0
        var earlyBirdCount = 0
    }

    static func summary(for tasks: [TaskItem],
                        asOf now: Date = .now,
                        calendar: Calendar = .current) -> Summary {
        var s = Summary()
        let today = calendar.startOfDay(for: now)

        // Per-completion aggregation.
        var categoriesWithDone: Set<String> = []
        for task in tasks where !task.isArchived {
            for c in (task.completions ?? []) where c.status == .done {
                s.totalCompleted += 1
                switch task.kind {
                case .chore: s.choreCompleted += 1
                case .habit: s.habitCompleted += 1
                }
                categoriesWithDone.insert(task.categoryRaw)
                if calendar.component(.hour, from: c.loggedAt) < 9 { s.earlyBirdCount += 1 }
            }
            s.longestStreak = max(s.longestStreak, SchedulingEngine.longestStreak(for: task, asOf: now, calendar: calendar))
            s.bestCurrentStreak = max(s.bestCurrentStreak, SchedulingEngine.currentStreak(for: task, asOf: now, calendar: calendar))
        }
        s.distinctCategories = categoriesWithDone.count

        // Points & level.
        s.totalPoints = s.totalCompleted * pointsPerCompletion
        s.level = level(forPoints: s.totalPoints)
        s.levelTitle = title(forLevel: s.level)
        let base = cumulativePoints(forLevel: s.level)
        let next = cumulativePoints(forLevel: s.level + 1)
        s.xpForLevelSpan = max(1, next - base)
        s.xpIntoLevel = s.totalPoints - base
        s.pointsToNextLevel = max(0, next - s.totalPoints)
        s.levelProgress = min(1, Double(s.xpIntoLevel) / Double(s.xpForLevelSpan))

        // Weekly goal (start of this week through today, so future days aren't "missed").
        if let week = calendar.dateInterval(of: .weekOfYear, for: today) {
            let span = DateInterval(start: week.start, end: today)
            for task in tasks where !task.isArchived {
                let occ = SchedulingEngine.occurrences(for: task, in: span, calendar: calendar)
                s.scheduledThisWeek += occ.count
                s.completedThisWeek += occ.filter { task.isCompleted(on: $0, calendar: calendar) }.count
            }
            s.weeklyProgress = s.scheduledThisWeek == 0 ? 0 : Double(s.completedThisWeek) / Double(s.scheduledThisWeek)
        }

        s.perfectWeekCount = Self.perfectWeekCount(tasks: tasks, asOf: today, calendar: calendar)
        return s
    }

    /// Counts fully-elapsed calendar weeks (within the last 16) in which every
    /// scheduled occurrence (at least one) was completed.
    private static func perfectWeekCount(tasks: [TaskItem], asOf today: Date, calendar: Calendar) -> Int {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }
        var count = 0
        for offset in 1...16 {
            guard let dayInWeek = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek.start),
                  let week = calendar.dateInterval(of: .weekOfYear, for: dayInWeek) else { continue }
            let span = DateInterval(start: week.start, end: calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end)
            var scheduled = 0, done = 0
            for task in tasks where !task.isArchived {
                let occ = SchedulingEngine.occurrences(for: task, in: span, calendar: calendar)
                scheduled += occ.count
                done += occ.filter { task.isCompleted(on: $0, calendar: calendar) }.count
            }
            if scheduled > 0 && done == scheduled { count += 1 }
        }
        return count
    }

    // MARK: - Level math

    /// Cumulative points required to *reach* `level` (level 1 == 0). Triangular curve:
    /// L1 0, L2 100, L3 300, L4 600, L5 1000, L6 1500 …
    static func cumulativePoints(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return 50 * (level - 1) * level
    }

    static func level(forPoints points: Int) -> Int {
        var l = 1
        while cumulativePoints(forLevel: l + 1) <= points { l += 1 }
        return l
    }

    static func title(forLevel level: Int) -> String {
        switch level {
        case ...1:  return String(localized: "Beginner")
        case 2:     return String(localized: "Novice")
        case 3:     return String(localized: "Apprentice")
        case 4:     return String(localized: "Achiever")
        case 5:     return String(localized: "Pro")
        case 6:     return String(localized: "Expert")
        case 7:     return String(localized: "Master")
        default:    return String(localized: "Legend")
        }
    }

    // MARK: - Tiered badges

    /// A badge *family*: one metric with several escalating tiers (Bronze, Silver,
    /// Gold …). The user keeps levelling up the same badge as their metric grows.
    struct Achievement: Identifiable {
        let id: String
        let name: String
        let systemImage: String
        /// Noun for the metric, e.g. "tasks", "day streak".
        let unit: String
        /// Ascending goals. tier 1 is reached at tiers[0], etc.
        let tiers: [Int]
        /// Current value of the tracked metric.
        let metric: (Summary) -> Int

        func value(_ s: Summary) -> Int { metric(s) }

        /// How many tiers have been reached (0 = locked, up to `tiers.count`).
        func tierReached(_ s: Summary) -> Int { tiers.filter { $0 <= metric(s) }.count }

        func isMaxed(_ s: Summary) -> Bool { tierReached(s) >= tiers.count }

        /// The goal of the next unreached tier, or nil if maxed out.
        func nextGoal(_ s: Summary) -> Int? {
            let reached = tierReached(s)
            return reached < tiers.count ? tiers[reached] : nil
        }
    }

    static let achievements: [Achievement] = [
        Achievement(id: "task_completer", name: String(localized: "Task Completer"),
                    systemImage: "checkmark.seal.fill", unit: String(localized: "tasks"),
                    tiers: [1, 10, 50, 100, 250]) { $0.totalCompleted },
        Achievement(id: "streak_keeper", name: String(localized: "Streak Keeper"),
                    systemImage: "flame.fill", unit: String(localized: "day streak"),
                    tiers: [3, 7, 14, 30, 100]) { $0.longestStreak },
        Achievement(id: "chore_champion", name: String(localized: "Chore Champion"),
                    systemImage: "house.fill", unit: String(localized: "chores"),
                    tiers: [10, 25, 75, 150]) { $0.choreCompleted },
        Achievement(id: "habit_hero", name: String(localized: "Habit Hero"),
                    systemImage: "heart.fill", unit: String(localized: "habits"),
                    tiers: [10, 25, 75, 150]) { $0.habitCompleted },
        Achievement(id: "climber", name: String(localized: "Climber"),
                    systemImage: "arrow.up.circle.fill", unit: String(localized: "level"),
                    tiers: [2, 3, 5, 8, 12]) { $0.level },
        Achievement(id: "perfectionist", name: String(localized: "Perfectionist"),
                    systemImage: "rosette", unit: String(localized: "perfect weeks"),
                    tiers: [1, 4, 12]) { $0.perfectWeekCount },
        Achievement(id: "well_rounded", name: String(localized: "Well-Rounded"),
                    systemImage: "circle.hexagongrid.fill", unit: String(localized: "categories"),
                    tiers: [3, 5, 7]) { $0.distinctCategories },
        Achievement(id: "early_bird", name: String(localized: "Early Bird"),
                    systemImage: "sunrise.fill", unit: String(localized: "before 9 AM"),
                    tiers: [1, 10, 50]) { $0.earlyBirdCount },
    ]

    /// Total number of tiers across every badge family.
    static var totalTiers: Int { achievements.reduce(0) { $0 + $1.tiers.count } }

    /// Number of tiers the user has unlocked across every family.
    static func tiersEarned(in summary: Summary) -> Int {
        achievements.reduce(0) { $0 + $1.tierReached(summary) }
    }
}

/// Persists the highest tier already celebrated for each badge family, so a
/// celebration fires exactly once per newly reached tier. Shared by Today & Awards.
@MainActor
enum AchievementTracker {
    private static let key = "seenBadgeTiers"

    /// Records the current tiers and returns whether any new tier was reached
    /// since the last call — i.e. whether to celebrate.
    @discardableResult
    static func registerAndCheck(_ summary: GamificationEngine.Summary) -> Bool {
        let defaults = UserDefaults.standard

        // Stored as "id:tier" pairs, comma-separated.
        var seen: [String: Int] = [:]
        for pair in (defaults.string(forKey: key) ?? "").split(separator: ",") {
            let parts = pair.split(separator: ":")
            if parts.count == 2, let tier = Int(parts[1]) { seen[String(parts[0])] = tier }
        }

        var unlockedSomething = false
        for badge in GamificationEngine.achievements {
            let tier = badge.tierReached(summary)
            if tier > (seen[badge.id] ?? 0) {
                unlockedSomething = true
                seen[badge.id] = tier
            }
        }

        if unlockedSomething {
            let encoded = seen.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            defaults.set(encoded, forKey: key)
        }
        return unlockedSomething
    }
}
