import Foundation

/// Lightweight, offline content filtering for user-entered text (handles and
/// display names). This is a first line of defence to satisfy the "filter
/// objectionable content" requirement for user-generated content; it is not a
/// substitute for the report/block flow.
enum ContentModeration {
    /// A conservative substring blocklist. Kept intentionally small here; expand
    /// as needed. Matching is case-insensitive and substring-based.
    private static let blocked: [String] = [
        "fuck", "shit", "bitch", "cunt", "nigger", "nigga", "faggot", "fag",
        "slut", "whore", "rape", "nazi", "retard", "kike", "spic", "dyke",
    ]

    /// Returns true if the text contains no blocked terms.
    static func isAcceptable(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !blocked.contains { lower.contains($0) }
    }
}
