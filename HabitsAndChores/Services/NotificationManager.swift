import Foundation
import UserNotifications

/// Schedules local reminder notifications for tasks that have a reminder time.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private init() {}

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// (Re)schedules reminders for every task. Call on launch / foreground so the
    /// finite rolling window of `.everyN` one-shot triggers is refreshed before it
    /// runs out (otherwise those reminders silently stop until the task is edited).
    func rescheduleAll(_ tasks: [TaskItem]) async {
        for task in tasks { await reschedule(for: task) }
    }

    /// (Re)schedules reminders for a single task. Removes any prior requests for it first.
    func reschedule(for task: TaskItem) async {
        // Await the cancellation before re-adding so a slow removal can't race ahead
        // and wipe the freshly-scheduled requests, leaving duplicates or none.
        await cancelPending(taskID: task.id)
        guard task.hasReminder, !task.isArchived,
              let hour = task.reminderHour, let minute = task.reminderMinute else { return }

        let rule = task.frequency
        switch rule.kind {
        case .daily:
            await add(taskID: task.id, title: task.title, body: task.details,
                      dateComponents: DateComponents(hour: hour, minute: minute), repeats: true, suffix: "daily")

        case .weekly:
            for weekday in rule.weekdays {
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = hour
                comps.minute = minute
                await add(taskID: task.id, title: task.title, body: task.details,
                          dateComponents: comps, repeats: true, suffix: "wd\(weekday)")
            }

        case .monthly:
            var comps = DateComponents()
            comps.day = rule.dayOfMonth ?? 1
            comps.hour = hour
            comps.minute = minute
            await add(taskID: task.id, title: task.title, body: task.details,
                      dateComponents: comps, repeats: true, suffix: "monthly")

        case .everyN, .floating:
            // Calendar triggers can't express arbitrary N-day intervals (and a floating
            // task has no fixed weekday). Schedule a rolling window of the next 30
            // occurrences as one-shot triggers — for floating these are the period
            // starts (each week/month), nudging at the chosen time.
            let cal = Calendar.current
            let now = Date()
            guard let end = cal.date(byAdding: .day, value: 120, to: now) else { return }
            let occ = SchedulingEngine.occurrences(for: task, in: DateInterval(start: now, end: end), calendar: cal)
            for (idx, day) in occ.prefix(30).enumerated() {
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = hour
                comps.minute = minute
                await add(taskID: task.id, title: task.title, body: task.details,
                          dateComponents: comps, repeats: false, suffix: "n\(idx)")
            }
        }
    }

    // MARK: - To-dos

    /// Schedules (or clears) a to-do reminder: at a fixed time, relative to its due
    /// date, or repeating daily until it's done.
    func reschedule(todo: TodoItem) async {
        cancelTodo(id: todo.id)
        guard !todo.isDone else { return }

        let cal = Calendar.current
        let content = UNMutableNotificationContent()
        content.title = String(localized: "To-Do")
        content.body = todo.title
        content.sound = .default

        let trigger: UNCalendarNotificationTrigger?
        switch todo.reminderMode {
        case .none:
            trigger = nil
        case .atTime:
            guard let date = todo.reminderDate, date > .now else { return }
            trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        case .beforeDue:
            guard let due = todo.dueDate else { return }
            let fire = due.addingTimeInterval(-todo.reminderOffset)
            guard fire > .now else { return }
            trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        case .dailyUntilDone:
            guard let time = todo.reminderDate else { return }
            trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.hour, .minute], from: time), repeats: true)
        }

        guard let trigger else { return }
        let request = UNNotificationRequest(identifier: "todo-\(todo.id.uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelTodo(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["todo-\(id.uuidString)"])
    }

    // MARK: - Shared household tasks

    private static let sharedPrefix = "shared-"

    /// Cancels all shared-task reminders, then schedules them afresh for every
    /// shared task that has a reminder. Idempotent, so it can run after each sync.
    func rescheduleShared(_ chores: [SharedChore]) async {
        await cancelAllShared()
        for chore in chores where chore.hasReminder {
            if chore.isTodo {
                await scheduleSharedTodo(chore)
            } else {
                await scheduleSharedChore(chore)
            }
        }
    }

    private func cancelAllShared() async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.sharedPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func scheduleSharedChore(_ chore: SharedChore) async {
        guard let hour = chore.reminderHour, let minute = chore.reminderMinute else { return }
        let id = Self.sharedPrefix + chore.id
        let rule = chore.frequency
        switch rule.kind {
        case .daily:
            await addShared(id: id, suffix: "daily", title: chore.title, body: chore.details,
                            components: DateComponents(hour: hour, minute: minute), repeats: true)
        case .weekly:
            for weekday in rule.weekdays {
                await addShared(id: id, suffix: "wd\(weekday)", title: chore.title, body: chore.details,
                                components: DateComponents(hour: hour, minute: minute, weekday: weekday), repeats: true)
            }
        case .monthly:
            await addShared(id: id, suffix: "monthly", title: chore.title, body: chore.details,
                            components: DateComponents(day: rule.dayOfMonth ?? 1, hour: hour, minute: minute), repeats: true)
        case .everyN, .floating:
            let cal = Calendar.current
            let now = Date()
            guard let end = cal.date(byAdding: .day, value: 120, to: now) else { return }
            let occ = SchedulingEngine.occurrences(frequency: rule, anchor: chore.createdAt,
                                                   in: DateInterval(start: now, end: end), calendar: cal)
            for (idx, day) in occ.prefix(30).enumerated() {
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = hour
                comps.minute = minute
                await addShared(id: id, suffix: "n\(idx)", title: chore.title, body: chore.details,
                                components: comps, repeats: false)
            }
        }
    }

    private func scheduleSharedTodo(_ chore: SharedChore) async {
        guard !chore.isDone else { return }
        let cal = Calendar.current
        let components: DateComponents
        let repeats: Bool
        switch chore.todoReminderMode {
        case .none:
            return
        case .atTime:
            guard let date = chore.reminderDate, date > .now else { return }
            components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            repeats = false
        case .beforeDue:
            guard let due = chore.dueDate else { return }
            let fire = due.addingTimeInterval(-chore.reminderOffset)
            guard fire > .now else { return }
            components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            repeats = false
        case .dailyUntilDone:
            guard let time = chore.reminderDate else { return }
            components = cal.dateComponents([.hour, .minute], from: time)
            repeats = true
        }
        await addShared(id: Self.sharedPrefix + chore.id, suffix: "todo",
                        title: String(localized: "To-Do"), body: chore.title,
                        components: components, repeats: repeats)
    }

    private func addShared(id: String, suffix: String, title: String, body: String,
                           components: DateComponents, repeats: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body.isEmpty ? String(localized: "Time to get this done.") : body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(identifier: "\(id)-\(suffix)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Fire-and-forget cancellation, for callers (archive/delete swipes) that don't
    /// immediately re-add and so don't care about ordering.
    func cancel(taskID: UUID) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(taskID.uuidString) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Awaitable cancellation, used by `reschedule(for:)` so the removal completes
    /// before new requests are added.
    private func cancelPending(taskID: UUID) async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(taskID.uuidString) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func add(taskID: UUID, title: String, body: String,
                     dateComponents: DateComponents, repeats: Bool, suffix: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body.isEmpty ? String(localized: "Time to get this done.") : body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
        let request = UNNotificationRequest(identifier: "\(taskID.uuidString)-\(suffix)", content: content, trigger: trigger)
        try? await center.add(request)
    }
}
