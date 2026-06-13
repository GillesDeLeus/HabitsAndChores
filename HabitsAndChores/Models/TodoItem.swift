import Foundation
import SwiftData

/// A one-off to-do, independent of the recurring habits/chores system. No
/// scheduling, no streaks — just a thing to do once and check off.
@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date.now
    var completedAt: Date?

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.isDone = false
        self.createdAt = .now
        self.completedAt = nil
    }

    func toggle() {
        isDone.toggle()
        completedAt = isDone ? .now : nil
    }
}
