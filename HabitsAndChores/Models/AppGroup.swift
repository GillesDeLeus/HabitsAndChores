import Foundation

/// Shared App Group so the app and the widget read/write the **same** SwiftData
/// store. Without this they each open a private store in their own sandbox and the
/// widget sees no data. Both targets declare this group in their entitlements.
enum AppGroup {
    static let id = "group.com.beullens.homesuite.HabitsAndChores"
}
