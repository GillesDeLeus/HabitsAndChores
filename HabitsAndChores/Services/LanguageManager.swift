import Foundation
import Observation

private var languageAssociationKey: UInt8 = 0

/// A `Bundle` subclass that, once installed on `Bundle.main`, resolves localized
/// strings from a chosen `.lproj` so the in-app language can change **live**
/// (no relaunch). `String(localized:)` and SwiftUI `Text` both route through here.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = objc_getAssociatedObject(self, &languageAssociationKey) as? String,
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    private static let installOverride: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()

    /// Forces the main bundle to resolve strings in `code` (e.g. "fr"), or to follow
    /// the system language when `code` is nil / "system".
    static func setAppLanguage(_ code: String?) {
        _ = installOverride
        let path = (code != nil && code != "system")
            ? Bundle.main.path(forResource: code, ofType: "lproj")
            : nil
        objc_setAssociatedObject(Bundle.main, &languageAssociationKey, path, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// Owns the in-app language selection. Injected into the environment; changing
/// `code` re-resolves strings immediately (the root view rebuilds on its value).
@MainActor
@Observable
final class LanguageManager {
    static let key = "appLanguage"

    var code: String {
        didSet { apply() }
    }

    init() {
        code = UserDefaults.standard.string(forKey: Self.key) ?? "system"
        apply()
    }

    /// Locale for date/number formatting (separate from string resolution).
    var locale: Locale { code == "system" ? .autoupdatingCurrent : Locale(identifier: code) }

    private func apply() {
        UserDefaults.standard.set(code, forKey: Self.key)
        // Drop any legacy AppleLanguages override so the bundle swizzle is the single
        // source of truth.
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        Bundle.setAppLanguage(code)
    }
}
