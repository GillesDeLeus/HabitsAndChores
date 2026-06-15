import Foundation
import CloudKit
import OSLog

/// A durable, on-disk queue of pending household writes. Optimistic mutations are
/// enqueued before the network call, so a change made offline (or while the app is
/// killed mid-sync) survives and is replayed on the next launch/foreground. Ops are
/// idempotent (client-assigned record names), so retries never duplicate data.
@MainActor
final class HouseholdOutbox {
    private let service: HouseholdService
    private var queue: [HouseholdMutation]
    private var draining = false

    init(service: HouseholdService) {
        self.service = service
        queue = Self.load()
    }

    var hasPending: Bool { !queue.isEmpty }

    func enqueue(_ mutation: HouseholdMutation) {
        queue.append(mutation)
        save()
    }

    /// Sends queued ops in order, stopping at the first transient failure (to retry
    /// later). Permanent failures are dropped so the queue can't get stuck.
    func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while let next = queue.first {
            do {
                try await service.apply(next)
                queue.removeFirst()
                save()
            } catch let error as CKError where Self.isTransient(error) {
                break   // keep it; retry on the next drain
            } catch {
                Logger.cloudkit.error("outbox dropping op \(next.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                queue.removeFirst()
                save()
            }
        }
    }

    private static func isTransient(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .notAuthenticated, .operationCancelled, .serverResponseLost:
            return true
        default:
            return false
        }
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("household_outbox.json")
    }

    private static func load() -> [HouseholdMutation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([HouseholdMutation].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(queue).write(to: Self.fileURL, options: .atomic)
        } catch {
            Logger.persistence.error("outbox save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
