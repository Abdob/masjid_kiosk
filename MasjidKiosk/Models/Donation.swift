import Foundation

/// One donation: a whole-dollar amount the donor chose.
struct Donation: Equatable {
    let dollars: Int

    /// Amount in the smallest currency unit (cents), as Square expects.
    var amountCents: Int { dollars * 100 }

    var formattedAmount: String { Self.format(dollars) }

    /// Note attached to the Square payment so it's identifiable in reports.
    var paymentNote: String { "Kiosk donation \(formattedAmount)" }

    /// "$1,250" — whole dollars, grouped.
    static func format(_ dollars: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return "$" + (formatter.string(from: NSNumber(value: dollars)) ?? "\(dollars)")
    }
}

/// A US phone number as typed on the kiosk keypad: up to ten digits.
struct PhoneNumber: Equatable {
    static let length = 10

    private(set) var digits = ""

    var isComplete: Bool { digits.count == Self.length }

    mutating func append(_ digit: Int) {
        // A leading 1 is the country code, not part of the number.
        guard digits.count < Self.length, !(digits.isEmpty && digit <= 1) else { return }
        digits.append(String(digit))
    }

    mutating func deleteLast() {
        if !digits.isEmpty { digits.removeLast() }
    }

    mutating func clear() { digits = "" }

    /// "(555) 123-4567", filled in progressively while typing.
    var formatted: String {
        let d = Array(digits)
        guard !d.isEmpty else { return "" }
        var out = "(" + String(d.prefix(3))
        if d.count > 3 { out += ") " + String(d[3..<min(6, d.count)]) }
        if d.count > 6 { out += "-" + String(d[6...]) }
        return out
    }

    /// "+15551234567", the form Square stores and searches on.
    var e164: String { "+1" + digits }
}
