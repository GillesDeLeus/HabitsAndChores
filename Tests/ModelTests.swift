import XCTest
@testable import HabitsAndChores

final class ModelTests: XCTestCase {

    func testTaskItemDerivedValues() {
        let t = TaskItem(title: "Walk", kind: .habit, category: .health, frequency: .daily,
                         reminderHour: 8, reminderMinute: 30)
        XCTAssertEqual(t.kind, .habit)
        XCTAssertEqual(t.category, .health)
        XCTAssertTrue(t.hasReminder)

        let noReminder = TaskItem(title: "x", kind: .chore, category: .home, frequency: .daily)
        XCTAssertFalse(noReminder.hasReminder)
        XCTAssertEqual(noReminder.symbolName, TaskCategory.home.symbolName, "defaults to category symbol")
    }

    func testCompletionNormalizesToStartOfDay() {
        let cal = Calendar.current
        let middseveral = cal.date(bySettingHour: 14, minute: 37, second: 5, of: .now)!
        let c = Completion(scheduledDate: middseveral, status: .done)
        XCTAssertEqual(c.scheduledDate, cal.startOfDay(for: middseveral))
        XCTAssertEqual(c.status, .done)
    }

    func testTodoToggleAndOverdue() {
        let todo = TodoItem(title: "Buy milk")
        XCTAssertFalse(todo.isDone)
        XCTAssertNil(todo.completedAt)

        todo.toggle()
        XCTAssertTrue(todo.isDone)
        XCTAssertNotNil(todo.completedAt)

        todo.toggle()
        XCTAssertFalse(todo.isDone)
        XCTAssertNil(todo.completedAt)
    }

    func testTodoOverdueOnlyWhenDueAndOpen() {
        let todo = TodoItem(title: "Pay bill")
        XCTAssertFalse(todo.isOverdue, "no due date")
        todo.dueDate = Date.now.addingTimeInterval(-3600)   // an hour ago
        XCTAssertTrue(todo.isOverdue)
        todo.toggle()                                       // done
        XCTAssertFalse(todo.isOverdue, "completed items aren't overdue")
    }

    func testTodoPriorityGetSet() {
        let todo = TodoItem(title: "t")
        XCTAssertEqual(todo.priority, .none)
        todo.priority = .high
        XCTAssertEqual(todo.priorityRaw, TodoPriority.high.rawValue)
    }
}
