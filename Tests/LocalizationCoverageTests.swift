import XCTest

/// Guards that the String Catalog stays fully translated for every advertised
/// language. The localization machinery (live `Bundle` swizzle in
/// `LanguageManager`) works regardless of coverage, so an untranslated key fails
/// silently at runtime by falling back to English. This test makes that loud:
/// any non-stale key missing a translated value in any shipping language fails CI.
///
/// It reads the source catalog directly from disk (resolved relative to this
/// file) rather than a bundled copy, so it works in the host-app-less logic
/// test target.
final class LocalizationCoverageTests: XCTestCase {

    /// Languages the app advertises (`CFBundleLocalizations` in project.yml),
    /// minus the `en` source language.
    static let targetLanguages = ["fr", "nl", "it", "pl", "es", "de"]

    private func catalogURL() throws -> URL {
        // .../Tests/LocalizationCoverageTests.swift -> repo root -> catalog
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("HabitsAndChores")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("String Catalog not found at \(url.path)")
        }
        return url
    }

    func testEveryStringIsTranslatedInAllLanguages() throws {
        let url = try catalogURL()
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        var failures: [String] = []
        for (key, raw) in strings {
            guard let entry = raw as? [String: Any] else { continue }
            // Stale keys are no longer referenced in source; they don't ship.
            if (entry["extractionState"] as? String) == "stale" { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for lang in Self.targetLanguages {
                let unit = (localizations[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                let state = unit?["state"] as? String
                if value == nil || value?.isEmpty == true || state == "new" {
                    failures.append("[\(lang)] missing/untranslated: \(key)")
                }
            }
        }

        if !failures.isEmpty {
            let sample = failures.prefix(25).joined(separator: "\n")
            XCTFail("\(failures.count) untranslated catalog entries (showing up to 25):\n\(sample)")
        }
    }
}
