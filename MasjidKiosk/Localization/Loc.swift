import Foundation

/// Donor-facing copy, looked up from `en.lproj/Localizable.strings`.
///
/// All wording lives in that one file so it can be changed — or a second
/// language added — without touching the views.
enum Loc {
    /// The string for `key`, with any `%@` / `%d` placeholders filled in.
    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        #if DEBUG
        // A missing key otherwise reaches the donor as the raw key text.
        if format == key { NSLog("Loc: no string for '\(key)'") }
        #endif
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}
