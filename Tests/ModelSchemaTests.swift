import XCTest
import SwiftData
@testable import HabitsAndChores

final class ModelSchemaTests: XCTestCase {

    /// Guards that the SwiftData schema stays valid for CloudKit mirroring: every
    /// attribute must be optional or have a default value. This reproduces — and
    /// now prevents a regression of — the bug where the app silently fell back to
    /// a local-only store because `TaskItem`/`Completion` lacked attribute defaults.
    func testSchemaIsCloudKitCompatible() throws {
        // Default ModelConfiguration uses cloudKitDatabase == .automatic, which runs
        // the CloudKit schema validation that previously failed.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        XCTAssertNoThrow(
            try ModelContainer(for: TaskItem.self, Completion.self, TodoItem.self,
                               configurations: config)
        )
    }
}
