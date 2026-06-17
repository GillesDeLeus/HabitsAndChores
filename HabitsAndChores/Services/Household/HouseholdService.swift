import Foundation
import CloudKit
import OSLog

extension Notification.Name {
    /// Posted when a household share is accepted or data changes.
    static let householdsChanged = Notification.Name("householdsChanged")
}

// MARK: - Models

/// A participant in a household, with their best-available display name and role.
struct HouseholdMember: Identifiable, Hashable {
    let id: String                  // CloudKit user record name (or a fallback)
    let name: String                // display name (CloudKit name / app display name / role fallback)
    let isOwner: Bool
    let isCurrentUser: Bool
    /// True when `name` is a real resolved name, not the generic "Owner"/"Member" fallback.
    let hasResolvedName: Bool
}

/// A shared group (couple / household) backed by a CKShare on a custom zone.
struct Household: Identifiable {
    let id: String                  // root record name
    let name: String
    let zoneID: CKRecordZone.ID
    let scope: CKDatabase.Scope     // .private if I own it, .shared if shared with me
    let members: [HouseholdMember]  // participants
    var chores: [SharedChore]
    /// Self-published member display names, keyed by CloudKit user record name, so
    /// every member can show every other member's real name (CloudKit won't share
    /// other users' names directly). Stored on the household root record.
    let nameByRecordName: [String: String]

    var isOwner: Bool { scope == .private }

    /// Display names for assignment (e.g. the assignee picker).
    var memberNames: [String] { members.map(\.name) }
}

/// A single "X completed Y" event in a household, for the fairness/activity view.
struct CompletionEvent: Identifiable {
    let id: String
    let choreTitle: String
    let completedBy: String      // member display name
    let date: Date
}

/// A portable reference to a household's CloudKit zone + database scope, so a
/// pending write can be persisted and replayed (the outbox).
struct ZoneRef: Codable {
    let zoneName: String
    let ownerName: String
    let scopeRaw: Int
    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }
    var scope: CKDatabase.Scope { CKDatabase.Scope(rawValue: scopeRaw) ?? .private }
    init(_ household: Household) {
        zoneName = household.zoneID.zoneName
        ownerName = household.zoneID.ownerName
        scopeRaw = household.scope.rawValue
    }
    init(zoneName: String, ownerName: String, scopeRaw: Int) {
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.scopeRaw = scopeRaw
    }
}

/// A persisted, idempotent household write for the offline outbox. Record names are
/// assigned client-side so replaying a queued op is an upsert, never a duplicate.
enum HouseholdMutation: Codable, Identifiable {
    case upsertChore(opID: String, zone: ZoneRef, householdID: String, recordName: String, draft: ChoreDraft)
    case deleteChore(opID: String, zone: ZoneRef, recordName: String)
    case setCompletion(opID: String, zone: ZoneRef, choreRecordName: String, occurrence: Date, by: String, done: Bool, completionRecordName: String)
    case assign(opID: String, zone: ZoneRef, choreRecordName: String, member: String?)

    var id: String {
        switch self {
        case .upsertChore(let o, _, _, _, _), .deleteChore(let o, _, _),
             .setCompletion(let o, _, _, _, _, _, _), .assign(let o, _, _, _): return o
        }
    }
}

/// A pending invitation for the current user to join a household, delivered
/// in-app (like a friend request) instead of via a manual share link. Stored in
/// the public database and addressed to the invitee's social user id.
struct HouseholdInvite: Identifiable {
    let id: String                  // invite record name
    let householdID: String
    let householdName: String
    let inviterUserID: String
    let inviterName: String
    let inviteeUserID: String
    let shareURL: String            // the CKShare URL, used to accept in-app
}

/// A task that belongs to a household — either a recurring habit/chore (kind,
/// category, recurrence, icon, colour) or, when `isTodo` is true, a one-off
/// to-do (due date, priority, reminder). Optionally assigned to a member.
struct SharedChore: Identifiable {
    let id: String                  // record name
    var title: String
    var details: String
    var kindRaw: String
    var categoryRaw: String
    var frequency: FrequencyRule
    var symbolName: String
    var colorHue: Double
    var createdAt: Date             // recurrence anchor (CloudKit creation date)
    var assignee: String?           // member display name, or nil = unassigned
    var isDone: Bool                // completed for the current occurrence
    var completedBy: String?        // who completed the current occurrence

    // To-do discriminator + one-off fields. Defaulted so the existing positional
    // initializers (recurring chores) keep compiling unchanged.
    var isTodo: Bool = false
    var dueDate: Date? = nil
    var scheduledDate: Date? = nil  // to-do planned "do" day; surfaces in Today
    var priorityRaw: Int = 0
    var reminderModeRaw: Int = 0    // to-do reminder mode (TodoReminderMode)
    var reminderDate: Date? = nil
    var reminderOffset: Double = 0
    var reminderHour: Int? = nil    // recurring-chore reminder time-of-day
    var reminderMinute: Int? = nil
    /// When true, the assignee rotates to the next household member after each
    /// completion (round-robin). When false, it stays put.
    var rotates: Bool = false

    var kind: TaskKind { TaskKind(rawValue: kindRaw) ?? .chore }
    var category: TaskCategory { TaskCategory(rawValue: categoryRaw) ?? .other }
    var priority: TodoPriority { TodoPriority(rawValue: priorityRaw) ?? .none }
    var todoReminderMode: TodoReminderMode { TodoReminderMode(rawValue: reminderModeRaw) ?? .none }
    var hasReminder: Bool {
        isTodo ? todoReminderMode != .none : (reminderHour != nil && reminderMinute != nil)
    }
    /// A scheduled to-do that's not yet done and due to surface on/before `day`.
    func isScheduledTodo(onOrBefore day: Date, calendar: Calendar = .current) -> Bool {
        guard isTodo, !isDone, let scheduledDate else { return false }
        return calendar.startOfDay(for: scheduledDate) <= calendar.startOfDay(for: day)
    }
}

/// Editable fields for creating/updating a shared task (recurring chore or to-do).
/// `Codable` so pending writes can be persisted in the offline outbox.
struct ChoreDraft: Codable {
    var title = ""
    var details = ""
    var kind: TaskKind = .chore
    var category: TaskCategory = .home
    var symbolName = "house.fill"
    var colorHue = 0.58
    var frequency: FrequencyRule = .daily
    var assignee: String?

    // To-do fields (used when `isTodo` is true).
    var isTodo = false
    var dueDate: Date?
    var scheduledDate: Date?
    var priority: TodoPriority = .none
    var todoReminderMode: TodoReminderMode = .none
    var reminderDate: Date?
    var reminderOffset: Double = 0
    // Recurring-chore reminder time-of-day.
    var reminderHour: Int?
    var reminderMinute: Int?
    /// Rotate the assignee among members after each completion.
    var rotates = false

    init() {}

    init(_ chore: SharedChore) {
        title = chore.title
        details = chore.details
        kind = chore.kind
        category = chore.category
        symbolName = chore.symbolName
        colorHue = chore.colorHue
        frequency = chore.frequency
        assignee = chore.assignee
        isTodo = chore.isTodo
        dueDate = chore.dueDate
        scheduledDate = chore.scheduledDate
        priority = chore.priority
        todoReminderMode = chore.todoReminderMode
        reminderDate = chore.reminderDate
        reminderOffset = chore.reminderOffset
        reminderHour = chore.reminderHour
        reminderMinute = chore.reminderMinute
        rotates = chore.rotates
    }
}

enum HouseholdError: LocalizedError {
    case notOwner, noShare, participantNotFound, inviteeNeedsUpdate

    var errorDescription: String? {
        switch self {
        case .notOwner: return String(localized: "Only the household owner can add members.")
        case .noShare: return String(localized: "This household can't be shared.")
        case .participantNotFound: return String(localized: "That friend isn't reachable on iCloud yet.")
        case .inviteeNeedsUpdate: return String(localized: "That friend needs to update the app before they can be invited this way.")
        }
    }
}

// MARK: - Service

/// Direct CloudKit implementation of household sharing. Households are root
/// records in per-household custom zones in the owner's private database; a
/// `CKShare` on the root makes the zone (and its chores) available to invited
/// participants in their shared database.
struct HouseholdService {
    static let containerID = "iCloud.com.beullens.homesuite.HabitsAndChores"
    private static let zonePrefix = "household-"

    private var container: CKContainer { CKContainer(identifier: Self.containerID) }
    private func database(_ scope: CKDatabase.Scope) -> CKDatabase {
        scope == .shared ? container.sharedCloudDatabase : container.privateCloudDatabase
    }
    /// Public database — used for in-app household invitations (addressed by the
    /// invitee's social user id, like friend requests).
    private var publicDatabase: CKDatabase { container.publicCloudDatabase }

    private enum RecordType {
        static let household = "Household"
        static let chore = "SharedChore"
        static let completion = "SharedCompletion"
        static let invite = "HouseholdInvite"
    }

    /// Fixed completion key for to-dos (which have no recurring occurrence): a
    /// single done/not-done state stored as one `SharedCompletion` at this date.
    static let todoOccurrence = Date(timeIntervalSince1970: 0)

    /// Whether a chore is relevant to *me* for the **Today** list: assigned to me,
    /// unassigned (up for grabs), or something I completed for the current occurrence.
    /// The last clause is what keeps a chore I just finished visible (struck through)
    /// instead of vanishing the instant a rotating chore reassigns itself to the next
    /// member. It clears on its own when the occurrence resets (`isDone` goes false).
    /// `completedBy` must be stamped with the same `myName` used here (see `setDone`).
    static func isMineForToday(assignee: String?, isDone: Bool, completedBy: String?,
                               myName: String?) -> Bool {
        assignee == nil || assignee == myName || (isDone && completedBy == myName)
    }

    /// Round-robin assignee for a rotating chore. `names` is a stable (e.g. sorted)
    /// member order; advances to the next on completion, retreats on un-completion
    /// (so toggling done is symmetric). Returns nil only if there are no members.
    static func rotatedAssignee(names: [String], current: String?, done: Bool) -> String? {
        guard !names.isEmpty else { return nil }
        let index = current.flatMap { names.firstIndex(of: $0) }
        let next: Int
        if done {
            next = index.map { ($0 + 1) % names.count } ?? 0
        } else {
            next = index.map { ($0 - 1 + names.count) % names.count } ?? 0
        }
        return names[next]
    }

    /// The occurrence key used to record completion for a shared task.
    static func occurrence(for chore: SharedChore, asOf now: Date = .now, calendar cal: Calendar = .current) -> Date {
        chore.isTodo ? todoOccurrence
                     : currentOccurrence(for: chore.frequency, asOf: now, anchor: chore.createdAt, calendar: cal)
    }

    /// Start-of-day of the chore's current scheduled occurrence, used to key
    /// per-occurrence completion (so a weekly chore stays done until next week).
    static func currentOccurrence(for frequency: FrequencyRule, asOf now: Date = .now,
                                  anchor: Date = .now, calendar cal: Calendar = .current) -> Date {
        let today = cal.startOfDay(for: now)
        switch frequency.kind {
        case .daily:
            return today
        case .floating:
            // Keyed at the period start, so the chore stays done until next period.
            return SchedulingEngine.floatingPeriod(unit: frequency.unit, containing: today, calendar: cal)?.start ?? today
        case .everyN:
            // Align to the anchor (chore creation): the most recent occurrence <= today.
            let anchorDay = cal.startOfDay(for: anchor)
            guard anchorDay <= today else { return anchorDay }
            let interval = max(1, frequency.interval)
            switch frequency.unit {
            case .day:
                let days = cal.dateComponents([.day], from: anchorDay, to: today).day ?? 0
                return cal.date(byAdding: .day, value: -(days % interval), to: today) ?? today
            case .week:
                let days = cal.dateComponents([.day], from: anchorDay, to: today).day ?? 0
                let alignedWeeks = (days / 7) - ((days / 7) % interval)
                return cal.date(byAdding: .day, value: alignedWeeks * 7, to: anchorDay) ?? today
            case .month:
                let months = cal.dateComponents([.month], from: anchorDay, to: today).month ?? 0
                let alignedMonths = months - (months % interval)
                return cal.date(byAdding: .month, value: alignedMonths, to: anchorDay)
                    .map { cal.startOfDay(for: $0) } ?? today
            }
        case .weekly:
            let weekdays = Set(frequency.weekdays)
            guard !weekdays.isEmpty else { return today }
            for delta in 0..<7 {
                if let day = cal.date(byAdding: .day, value: -delta, to: today),
                   weekdays.contains(cal.component(.weekday, from: day)) {
                    return day
                }
            }
            return today
        case .monthly:
            let target = frequency.dayOfMonth ?? 1
            func occurrence(inMonthOf date: Date) -> Date? {
                guard let range = cal.range(of: .day, in: .month, for: date) else { return nil }
                var comps = cal.dateComponents([.year, .month], from: date)
                comps.day = min(target, range.count)
                return cal.date(from: comps).map { cal.startOfDay(for: $0) }
            }
            if let thisMonth = occurrence(inMonthOf: today), thisMonth <= today { return thisMonth }
            if let prev = cal.date(byAdding: .month, value: -1, to: today),
               let prevOcc = occurrence(inMonthOf: prev) { return prevOcc }
            return today
        }
    }

    func isAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Subscribes to the private + shared databases so members get a push (and the
    /// list refreshes) when anyone changes a household or chore. Saved once.
    func registerSubscriptions() async {
        let defaults = UserDefaults.standard
        let key = "household.subscribed"
        guard !defaults.bool(forKey: key) else { return }
        var allOK = true
        for (scope, id) in [(CKDatabase.Scope.private, "household-private"),
                            (CKDatabase.Scope.shared, "household-shared")] {
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            do {
                _ = try await database(scope).save(subscription)
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // Already exists — fine.
            } catch {
                allOK = false
                Logger.cloudkit.error("household subscription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if allOK { defaults.set(true, forKey: key) }
    }

    // MARK: Create

    /// Creates a new household + its CKShare, returning the share so the caller can
    /// present the system invitation UI.
    func createHousehold(name: String) async throws -> CKShare {
        let zone = CKRecordZone(zoneName: Self.zonePrefix + UUID().uuidString)
        _ = try await database(.private).save(zone)

        let root = CKRecord(recordType: RecordType.household,
                            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID))
        root["name"] = name
        root["createdAt"] = Date()

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = name as CKRecordValue
        share.publicPermission = .none

        let result = try await database(.private).modifyRecords(saving: [root, share], deleting: [])
        for (_, saveResult) in result.saveResults {
            if case .failure(let error) = saveResult { throw error }
        }
        return share
    }

    // MARK: Fetch

    struct DatabaseChangeProbe {
        let changed: Bool                 // a household zone was added/changed/deleted
        let token: CKServerChangeToken?   // advance to this for next time
        let expired: Bool                 // the previous token was too old; do a full fetch
    }

    /// Cheaply asks a database whether any household zone changed since `token`, via
    /// `CKFetchDatabaseChangesOperation`. Used to skip the full re-fetch when nothing
    /// changed. With a nil token (first run) it reports `changed == true`.
    func databaseChanges(scope: CKDatabase.Scope, since token: CKServerChangeToken?) async throws -> DatabaseChangeProbe {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)
            var changed = false
            let note: (CKRecordZone.ID) -> Void = { zoneID in
                if zoneID.zoneName.hasPrefix(Self.zonePrefix) { changed = true }
            }
            operation.recordZoneWithIDChangedBlock = note
            operation.recordZoneWithIDWasDeletedBlock = note
            operation.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let (newToken, _)):
                    continuation.resume(returning: DatabaseChangeProbe(changed: changed, token: newToken, expired: false))
                case .failure(let error as CKError) where error.code == .changeTokenExpired:
                    continuation.resume(returning: DatabaseChangeProbe(changed: true, token: nil, expired: true))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database(scope).add(operation)
        }
    }

    func households(currentUserRecordName: String? = nil, currentUserDisplayName: String = "") async throws -> [Household] {
        var result: [Household] = []
        for scope in [CKDatabase.Scope.private, .shared] {
            let db = database(scope)
            guard let zones = try? await db.allRecordZones() else { continue }
            for zone in zones where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
                guard let records = try? await allRecords(in: zone.zoneID, db: db),
                      let root = records.first(where: { $0.recordType == RecordType.household }) else { continue }
                let name = root["name"] as? String ?? "Household"

                let share = records.compactMap { $0 as? CKShare }.first
                // Self-published member names keyed by CloudKit user record name.
                let nameByRecordName = (root["memberNames"] as? Data)
                    .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
                let members = share.map {
                    householdMembers(of: $0, currentUserRecordName: currentUserRecordName,
                                     currentUserDisplayName: currentUserDisplayName,
                                     nameByRecordName: nameByRecordName)
                } ?? []

                // Group completion records by the chore they belong to.
                let cal = Calendar.current
                var completionsByChore: [String: [CKRecord]] = [:]
                for rec in records where rec.recordType == RecordType.completion {
                    if let choreID = rec["choreID"] as? String {
                        completionsByChore[choreID, default: []].append(rec)
                    }
                }

                let chores = records
                    .filter { $0.recordType == RecordType.chore }
                    .map { rec -> SharedChore in
                        let frequency = (rec["frequency"] as? Data)
                            .flatMap { try? JSONDecoder().decode(FrequencyRule.self, from: $0) } ?? .daily
                        let createdAt = rec.creationDate ?? .now
                        let isTodo = rec["isTodo"] as? Bool ?? false
                        // To-dos use a fixed completion key; recurring chores use their occurrence.
                        let occurrence = isTodo
                            ? Self.todoOccurrence
                            : Self.currentOccurrence(for: frequency, anchor: createdAt, calendar: cal)
                        let match = completionsByChore[rec.recordID.recordName]?.first {
                            isTodo
                                ? ($0["date"] as? Date) == occurrence
                                : ($0["date"] as? Date).map { cal.startOfDay(for: $0) } == occurrence
                        }
                        return SharedChore(
                            id: rec.recordID.recordName,
                            title: rec["title"] as? String ?? "",
                            details: rec["details"] as? String ?? "",
                            kindRaw: rec["kind"] as? String ?? TaskKind.chore.rawValue,
                            categoryRaw: rec["category"] as? String ?? TaskCategory.other.rawValue,
                            frequency: frequency,
                            symbolName: rec["symbol"] as? String ?? "checklist",
                            colorHue: rec["colorHue"] as? Double ?? 0.58,
                            createdAt: createdAt,
                            assignee: rec["assignee"] as? String,
                            isDone: match != nil,
                            completedBy: match?["completedBy"] as? String,
                            isTodo: isTodo,
                            dueDate: rec["dueDate"] as? Date,
                            scheduledDate: rec["scheduledDate"] as? Date,
                            priorityRaw: rec["priority"] as? Int ?? 0,
                            reminderModeRaw: rec["reminderMode"] as? Int ?? 0,
                            reminderDate: rec["reminderDate"] as? Date,
                            reminderOffset: rec["reminderOffset"] as? Double ?? 0,
                            reminderHour: rec["reminderHour"] as? Int,
                            reminderMinute: rec["reminderMinute"] as? Int,
                            rotates: rec["rotates"] as? Bool ?? false)
                    }
                    .sorted { $0.title < $1.title }

                result.append(Household(id: root.recordID.recordName, name: name,
                                        zoneID: zone.zoneID, scope: scope,
                                        members: members, chores: chores,
                                        nameByRecordName: nameByRecordName))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    // MARK: Chores

    func addChore(to household: Household, draft: ChoreDraft) async throws {
        let db = database(household.scope)
        let record = CKRecord(recordType: RecordType.chore,
                              recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: household.zoneID))
        // Parent link so the chore is shared together with the household root.
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        record.parent = CKRecord.Reference(recordID: rootID, action: .none)
        record["household"] = CKRecord.Reference(recordID: rootID, action: .deleteSelf)
        apply(draft, to: record)
        _ = try await db.save(record)
    }

    func updateChore(_ chore: SharedChore, draft: ChoreDraft, in household: Household) async throws {
        try await update(chore, in: household) { apply(draft, to: $0) }
    }

    /// Performs a queued mutation idempotently (used by the offline outbox). Re-running
    /// is safe: upserts use client-assigned record names, deletes tolerate a missing
    /// record, and completion toggles fetch-or-remove by occurrence.
    func apply(_ mutation: HouseholdMutation) async throws {
        switch mutation {
        case .upsertChore(_, let zone, let householdID, let recordName, let draft):
            let db = database(zone.scope)
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)
            let record = (try? await db.record(for: recordID)) ?? choreRecord(id: recordID, householdID: householdID, zone: zone)
            apply(draft, to: record)
            _ = try await db.save(record)

        case .deleteChore(_, let zone, let recordName):
            do {
                _ = try await database(zone.scope).deleteRecord(withID: CKRecord.ID(recordName: recordName, zoneID: zone.zoneID))
            } catch let error as CKError where error.code == .unknownItem {
                // Already gone — treat as success.
            }

        case .setCompletion(_, let zone, let choreRecordName, let occurrence, let by, let done, let completionRecordName):
            let db = database(zone.scope)
            let choreID = CKRecord.ID(recordName: choreRecordName, zoneID: zone.zoneID)
            if done {
                let record = CKRecord(recordType: RecordType.completion,
                                      recordID: CKRecord.ID(recordName: completionRecordName, zoneID: zone.zoneID))
                record["choreID"] = choreRecordName
                record["date"] = occurrence
                record["completedBy"] = by
                record.parent = CKRecord.Reference(recordID: choreID, action: .none)
                record["chore"] = CKRecord.Reference(recordID: choreID, action: .deleteSelf)
                _ = try await db.save(record)
            } else {
                let cal = Calendar.current
                let all = (try? await allRecords(in: zone.zoneID, db: db)) ?? []
                let targets = all.filter {
                    $0.recordType == RecordType.completion
                    && $0["choreID"] as? String == choreRecordName
                    && ($0["date"] as? Date).map { cal.startOfDay(for: $0) } == cal.startOfDay(for: occurrence)
                }
                for target in targets { _ = try? await db.deleteRecord(withID: target.recordID) }
            }

        case .assign(_, let zone, let choreRecordName, let member):
            let db = database(zone.scope)
            let record = try await db.record(for: CKRecord.ID(recordName: choreRecordName, zoneID: zone.zoneID))
            record["assignee"] = member
            _ = try await db.save(record)
        }
    }

    private func choreRecord(id: CKRecord.ID, householdID: String, zone: ZoneRef) -> CKRecord {
        let record = CKRecord(recordType: RecordType.chore, recordID: id)
        let rootID = CKRecord.ID(recordName: householdID, zoneID: zone.zoneID)
        record.parent = CKRecord.Reference(recordID: rootID, action: .none)
        record["household"] = CKRecord.Reference(recordID: rootID, action: .deleteSelf)
        return record
    }

    private func apply(_ draft: ChoreDraft, to record: CKRecord) {
        record["title"] = draft.title
        record["details"] = draft.details
        record["kind"] = draft.kind.rawValue
        record["category"] = draft.category.rawValue
        record["symbol"] = draft.symbolName
        record["colorHue"] = draft.colorHue
        record["assignee"] = draft.assignee
        record["frequency"] = try? JSONEncoder().encode(draft.frequency)
        record["isTodo"] = draft.isTodo
        record["dueDate"] = draft.dueDate
        record["scheduledDate"] = draft.scheduledDate
        record["priority"] = draft.priority.rawValue
        record["reminderMode"] = draft.todoReminderMode.rawValue
        record["reminderDate"] = draft.reminderDate
        record["reminderOffset"] = draft.reminderOffset
        record["reminderHour"] = draft.reminderHour
        record["reminderMinute"] = draft.reminderMinute
        record["rotates"] = draft.rotates
    }

    /// Marks/unmarks a chore done for its current occurrence by writing/removing a
    /// `SharedCompletion` record (recording who completed it).
    func setCompletion(_ chore: SharedChore, done: Bool, occurrence: Date, by: String,
                       in household: Household) async throws {
        let db = database(household.scope)
        let choreRecordID = CKRecord.ID(recordName: chore.id, zoneID: household.zoneID)
        if done {
            let record = CKRecord(recordType: RecordType.completion,
                                  recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: household.zoneID))
            record["choreID"] = chore.id
            record["date"] = occurrence
            record["completedBy"] = by
            record.parent = CKRecord.Reference(recordID: choreRecordID, action: .none)
            record["chore"] = CKRecord.Reference(recordID: choreRecordID, action: .deleteSelf)
            _ = try await db.save(record)
        } else {
            // Remove any completion for this chore at the current occurrence.
            let cal = Calendar.current
            let all = (try? await allRecords(in: household.zoneID, db: db)) ?? []
            let targets = all.filter {
                $0.recordType == RecordType.completion
                && $0["choreID"] as? String == chore.id
                && ($0["date"] as? Date).map { cal.startOfDay(for: $0) } == occurrence
            }
            for target in targets { _ = try? await db.deleteRecord(withID: target.recordID) }
        }
    }

    func assign(_ chore: SharedChore, to member: String?, in household: Household) async throws {
        try await update(chore, in: household) { $0["assignee"] = member }
    }

    func deleteChore(_ chore: SharedChore, in household: Household) async throws {
        let id = CKRecord.ID(recordName: chore.id, zoneID: household.zoneID)
        _ = try await database(household.scope).deleteRecord(withID: id)
    }

    /// All completion events in a household (who completed what, and when), newest
    /// first — for the fairness / activity view.
    func completionHistory(in household: Household) async throws -> [CompletionEvent] {
        let db = database(household.scope)
        let records = (try? await allRecords(in: household.zoneID, db: db)) ?? []
        let titleByChoreID = Dictionary(
            records.filter { $0.recordType == RecordType.chore }
                .map { ($0.recordID.recordName, $0["title"] as? String ?? "") },
            uniquingKeysWith: { a, _ in a })
        return records
            .filter { $0.recordType == RecordType.completion }
            .compactMap { rec -> CompletionEvent? in
                guard let by = rec["completedBy"] as? String, !by.isEmpty else { return nil }
                // Use the record's creation date as the real completion time (the
                // `date` field is the occurrence key, which is a sentinel for to-dos).
                let when = rec.creationDate ?? (rec["date"] as? Date) ?? .now
                let choreID = rec["choreID"] as? String ?? ""
                return CompletionEvent(id: rec.recordID.recordName,
                                       choreTitle: titleByChoreID[choreID] ?? String(localized: "A chore"),
                                       completedBy: by, date: when)
            }
            .sorted { $0.date > $1.date }
    }

    /// Clears the assignee on every chore currently assigned to `memberName`, so a
    /// member who leaves (or is removed) doesn't leave stale assignments behind.
    func unassignChores(assignedTo memberName: String, in household: Household) async throws {
        let db = database(household.scope)
        let all = (try? await allRecords(in: household.zoneID, db: db)) ?? []
        let targets = all.filter {
            $0.recordType == RecordType.chore && $0["assignee"] as? String == memberName
        }
        for record in targets {
            record["assignee"] = nil
            _ = try? await db.save(record)
        }
    }

    /// Deletes a household. The owner deletes the whole zone (removing it for
    /// everyone); a participant deletes their copy of the shared zone (leaving it).
    func deleteHousehold(_ household: Household) async throws {
        _ = try await database(household.scope).deleteRecordZone(withID: household.zoneID)
    }

    /// Adds an existing app friend (by their CloudKit user record name) to a
    /// household as a read-write member, without a manual invite link. The invitee
    /// must still accept per CloudKit's rules. Owner only.
    func addFriend(userRecordName: String, to household: Household) async throws {
        guard household.scope == .private else { throw HouseholdError.notOwner }
        let db = database(.private)
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        let root = try await db.record(for: rootID)
        guard let shareRef = root.share,
              let share = try await db.record(for: shareRef.recordID) as? CKShare else {
            throw HouseholdError.noShare
        }
        let participant = try await fetchParticipant(userRecordName: userRecordName)
        participant.permission = .readWrite
        share.addParticipant(participant)
        let result = try await db.modifyRecords(saving: [share], deleting: [])
        for (_, saveResult) in result.saveResults {
            if case .failure(let error) = saveResult { throw error }
        }
    }

    /// Removes a member from a household by revoking their share participation,
    /// identified by their CloudKit user record name. Owner only.
    func removeMember(recordName: String, from household: Household) async throws {
        guard household.scope == .private else { throw HouseholdError.notOwner }
        let db = database(.private)
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        let root = try await db.record(for: rootID)
        guard let shareRef = root.share,
              let share = try await db.record(for: shareRef.recordID) as? CKShare else {
            throw HouseholdError.noShare
        }
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == recordName
        }) else { throw HouseholdError.participantNotFound }
        share.removeParticipant(participant)
        let result = try await db.modifyRecords(saving: [share], deleting: [])
        for (_, saveResult) in result.saveResults {
            if case .failure(let error) = saveResult { throw error }
        }
    }

    private func fetchParticipant(userRecordName: String) async throws -> CKShare.Participant {
        let lookup = CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: userRecordName))
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookup])
            var participant: CKShare.Participant?
            operation.perShareParticipantResultBlock = { _, result in
                if case .success(let found) = result { participant = found }
            }
            operation.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    if let participant { continuation.resume(returning: participant) }
                    else { continuation.resume(throwing: HouseholdError.participantNotFound) }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    /// The CKShare for a household, for presenting the invitation UI (owner only).
    func share(for household: Household) async throws -> (CKShare, CKContainer)? {
        let db = database(household.scope)
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        guard let root = try? await db.record(for: rootID),
              let shareRef = root.share,
              let share = try? await db.record(for: shareRef.recordID) as? CKShare else { return nil }
        return (share, container)
    }

    /// Writes a member's display name onto the household root record's `memberNames`
    /// map (keyed by CloudKit user record name), so other members can show their real
    /// name. No-ops if the name is already current. Any member may call this for
    /// themselves (they have read-write on the shared zone).
    func publishMemberName(_ displayName: String, recordName: String, in household: Household) async throws {
        guard !recordName.isEmpty, !displayName.isEmpty else { return }
        let db = database(household.scope)
        let rootID = CKRecord.ID(recordName: household.id, zoneID: household.zoneID)
        let root = try await db.record(for: rootID)
        var map = (root["memberNames"] as? Data)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        guard map[recordName] != displayName else { return }
        map[recordName] = displayName
        root["memberNames"] = try? JSONEncoder().encode(map)
        _ = try await db.save(root)
    }

    // MARK: - In-app invitations

    /// Invites an existing app friend to a household in-app (no manual link):
    /// adds them as a share participant *and* writes a `HouseholdInvite` record in
    /// the public database, addressed to their social user id, carrying the share
    /// URL so they can accept from inside the app. Owner only.
    func invite(_ profile: SharedProfile, to household: Household,
                inviterUserID: String, inviterName: String) async throws {
        guard let recordName = profile.cloudUserRecordName else { throw HouseholdError.inviteeNeedsUpdate }
        // Authorize them on the share, then publish the invite carrying its URL.
        try await addFriend(userRecordName: recordName, to: household)
        // Seed their display name so members see it immediately (before they open the app).
        try? await publishMemberName(profile.displayName, recordName: recordName, in: household)
        guard let (share, _) = try await share(for: household), let url = share.url else {
            throw HouseholdError.noShare
        }
        let id = CKRecord.ID(recordName: "hhinvite_\(household.id)_\(profile.userID)")
        let record = CKRecord(recordType: RecordType.invite, recordID: id)
        record["inviter"] = inviterUserID
        record["invitee"] = profile.userID
        record["inviterName"] = inviterName
        record["householdName"] = household.name
        record["householdID"] = household.id
        record["shareURL"] = url.absoluteString
        record["createdAt"] = Date()
        _ = try await publicDatabase.save(record)
    }

    /// Pending household invitations addressed to the given user.
    func pendingInvites(for userID: String) async throws -> [HouseholdInvite] {
        let query = CKQuery(recordType: RecordType.invite,
                            predicate: NSPredicate(format: "invitee == %@", userID))
        do {
            let (matches, _) = try await publicDatabase.records(matching: query)
            return matches.compactMap { _, result in (try? result.get()).flatMap(Self.invite(from:)) }
        } catch let error as CKError where error.code == .unknownItem {
            return [] // record type not created yet — no invites
        }
    }

    /// Accepts an invitation: fetches the share metadata from its URL and accepts
    /// the `CKShare`, then removes the invite record.
    func acceptInvite(_ invite: HouseholdInvite) async throws {
        guard let url = URL(string: invite.shareURL) else { throw HouseholdError.noShare }
        let metadata = try await fetchShareMetadata(url)
        try await acceptShare(metadata)
        _ = try? await publicDatabase.deleteRecord(withID: CKRecord.ID(recordName: invite.id))
    }

    /// Declines (dismisses) an invitation by deleting its record.
    func declineInvite(_ invite: HouseholdInvite) async throws {
        _ = try await publicDatabase.deleteRecord(withID: CKRecord.ID(recordName: invite.id))
    }

    private func fetchShareMetadata(_ url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            var metadata: CKShare.Metadata?
            operation.perShareMetadataResultBlock = { _, result in
                if case .success(let found) = result { metadata = found }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let metadata { continuation.resume(returning: metadata) }
                    else { continuation.resume(throwing: HouseholdError.noShare) }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    private func acceptShare(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    static func invite(from record: CKRecord) -> HouseholdInvite? {
        guard let householdID = record["householdID"] as? String,
              let invitee = record["invitee"] as? String,
              let url = record["shareURL"] as? String else { return nil }
        return HouseholdInvite(
            id: record.recordID.recordName,
            householdID: householdID,
            householdName: record["householdName"] as? String ?? String(localized: "Household"),
            inviterUserID: record["inviter"] as? String ?? "",
            inviterName: record["inviterName"] as? String ?? String(localized: "A friend"),
            inviteeUserID: invitee,
            shareURL: url)
    }

    // MARK: - Helpers

    private func update(_ chore: SharedChore, in household: Household,
                        _ mutate: (CKRecord) -> Void) async throws {
        let db = database(household.scope)
        let id = CKRecord.ID(recordName: chore.id, zoneID: household.zoneID)
        let record = try await db.record(for: id)
        mutate(record)
        _ = try await db.save(record)
    }

    /// Fetches every record in a zone via zone changes — works in custom/shared
    /// zones without the queryable indexes that `CKQuery` would require.
    private func allRecords(in zoneID: CKRecordZone.ID, db: CKDatabase) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config])
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { records.append(record) }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: records)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            db.add(operation)
        }
    }

    /// Resolves each share participant to a `HouseholdMember`, keeping the display
    /// name and the role separate so the UI can show, e.g., the owner's name with
    /// an "Owner" subtitle rather than just "Owner".
    ///
    /// The current user (typically the owner viewing their own household) is
    /// identified via CloudKit's `currentUserParticipant` — record-name matching is
    /// unreliable because the owner's own participant often doesn't match the user
    /// record id fetched separately, and anonymous users have no such id at all.
    private func householdMembers(of share: CKShare, currentUserRecordName: String?,
                                  currentUserDisplayName: String,
                                  nameByRecordName: [String: String]) -> [HouseholdMember] {
        let formatter = PersonNameComponentsFormatter()
        let currentParticipant = share.currentUserParticipant
        return share.participants.enumerated().map { index, participant in
            let recordName = participant.userIdentity.userRecordID?.recordName
            let isOwner = participant.role == .owner
            let isCurrentUser = (currentParticipant != nil && participant == currentParticipant)
                || (recordName != nil && recordName == currentUserRecordName)

            // Best available name: the current user's own app display name first (we
            // know it and CloudKit won't hand us our own name); then the member's
            // self-published name; then a CloudKit name they've shared. Never the role.
            var resolved: String?
            if isCurrentUser, !currentUserDisplayName.isEmpty {
                resolved = currentUserDisplayName
            }
            if resolved == nil, let rn = recordName, let mapped = nameByRecordName[rn], !mapped.isEmpty {
                resolved = mapped
            }
            if resolved == nil, let components = participant.userIdentity.nameComponents {
                let name = formatter.string(from: components)
                if !name.isEmpty { resolved = name }
            }

            let hasResolvedName = resolved != nil
            let name = resolved ?? (isOwner ? String(localized: "Owner") : String(localized: "Member"))
            return HouseholdMember(id: recordName ?? "\(name)#\(index)", name: name,
                                   isOwner: isOwner, isCurrentUser: isCurrentUser,
                                   hasResolvedName: hasResolvedName)
        }
    }
}
