import SwiftUI

/// The languages a donor can switch the kiosk between.
enum KioskLanguage: String {
    case english = "en"
    case arabic = "ar"

    /// What the kiosk shows until a donor switches, and returns to afterwards.
    static let standard = KioskLanguage.english

    var other: KioskLanguage { self == .english ? .arabic : .english }

    /// The language's own name, for the button that switches to it.
    var name: String { self == .english ? "English" : "العربية" }

    var layoutDirection: LayoutDirection { self == .arabic ? .rightToLeft : .leftToRight }
}

/// Donor-facing copy, looked up from `<language>.lproj/Localizable.strings`.
///
/// All wording lives in those files so it can be changed — or another
/// language added — without touching the views.
enum Loc {
    /// The language `t` answers in. Owned by KioskFlowView, which redraws
    /// the screens when it changes; the iPad's own language is ignored.
    static var language = KioskLanguage.standard

    /// The string for `key`, with any `%@` / `%d` placeholders filled in.
    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        var format = strings(for: language).localizedString(forKey: key, value: missing, table: nil)
        if format == missing {
            format = strings(for: .english).localizedString(forKey: key, value: key, table: nil)
            #if DEBUG
            // A missing key otherwise reaches the donor in the wrong
            // language, or as the raw key text.
            NSLog("Loc: no \(language.rawValue) string for '\(key)'")
            #endif
        }
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    private static let missing = "\u{0}missing"

    private static func strings(for language: KioskLanguage) -> Bundle {
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}
