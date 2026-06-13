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

    /// (Re)schedules reminders for a single task. Removes any prior requests for it first.
    func reschedule(for task: TaskItem) async {
        cancel(taskID: task.id)
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

        case .everyN:
            // Calendar triggers can't express arbitrary N-day intervals. Schedule a
            // rolling window of the next 30 occurrences as one-shot triggers.
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

    /// Schedules (or clears) a one-shot reminder for a to-do.
    func reschedule(todo: TodoItem) async {
        cancelTodo(id: todo.id)
        guard !todo.isDone, let date = todo.reminderDate, date > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "To-Do")
        content.body = todo.title
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "todo-\(todo.id.uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelTodo(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["todo-\(id.uuidString)"])
    }

    func cancel(taskID: UUID) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(taskID.uuidString) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
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
