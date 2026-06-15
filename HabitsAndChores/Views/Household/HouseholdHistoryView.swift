import SwiftUI

/// Per-member fairness (who's pulling their weight) plus a recent-activity feed for
/// a household, built from `SharedCompletion` records.
struct HouseholdHistoryView: View {
    let householdID: String
    @Bindable var model: HouseholdsModel

    @State private var events: [CompletionEvent] = []
    @State private var loaded = false

    private var household: Household? { model.households.first { $0.id == householdID } }

    /// Completions in the last 30 days, for the fairness breakdown.
    private var recentWindow: [CompletionEvent] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return events.filter { $0.date >= cutoff }
    }

    /// (name, count) per member over the window — current members plus anyone who
    /// has completions but is no longer a member — sorted most-first.
    private var fairness: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in recentWindow { counts[event.completedBy, default: 0] += 1 }
        for member in household?.members ?? [] where counts[member.name] == nil {
            counts[member.name] = 0
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    private var windowTotal: Int { recentWindow.count }

    var body: some View {
        Group {
            if events.isEmpty && loaded {
                ContentUnavailableView("No activity yet", systemImage: "chart.bar.xaxis",
                                       description: Text("Completed chores will show up here, with each member's share."))
            } else {
                List {
                    Section {
                        ForEach(fairness, id: \.name) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.name)
                                    Spacer()
                                    Text("\(row.count)").foregroundStyle(.secondary).monospacedDigit()
                                }
                                ProgressView(value: Double(row.count), total: Double(max(fairness.first?.count ?? 1, 1)))
                                    .tint(.accentColor)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Last 30 days")
                    } footer: {
                        Text(windowTotal == 0
                             ? "No chores completed in the last 30 days."
                             : "\(windowTotal) chore(s) completed — bars show each member's share.")
                    }

                    Section("Recent activity") {
                        ForEach(events.prefix(40)) { event in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(event.completedBy) · \(event.choreTitle)")
                                    Text(event.date.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fairness & activity")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if !loaded { ProgressView() } }
        .task {
            guard let household else { loaded = true; return }
            events = await model.completionHistory(for: household)
            loaded = true
        }
        .refreshable {
            if let household { events = await model.completionHistory(for: household) }
        }
    }
}
