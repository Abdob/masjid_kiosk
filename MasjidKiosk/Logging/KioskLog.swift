import Foundation

/// The kiosk's own record of every donation: one CSV line each, one file
/// per day in the app's Documents directory, collected with
/// `curl` (see README.md). It is the one place a donor's phone number is
/// tied to the payment they made.
///
/// Logging never interferes with a donation: every failure here is swallowed.
/// Money has already changed hands by the time most rows are written, and a
/// full disk must not take the kiosk down.
actor KioskLog {

    static let shared = KioskLog()

    private static let header =
        "timestamp,amount,status,phone,payment_id,saved_to_square,note\n"

    /// What happened to a donation, as the `status` column spells it.
    enum Status: String {
        case ok              // paid
        case declined        // the card or the reader said no; nothing taken
        case unconfirmed = "UNCONFIRMED" // can't tell whether it was paid — check Square
    }

    /// Record one donation attempt, however it ended. `phone` is nil when
    /// the donor skipped it; `savedToSquare` is nil when not attempted.
    func record(
        _ donation: Donation,
        status: Status,
        phone: PhoneNumber? = nil,
        paymentID: String? = nil,
        savedToSquare: Bool? = nil,
        note: String = ""
    ) {
        let fields = [
            Self.timestamp(),
            String(donation.dollars),
            status.rawValue,
            phone?.formatted ?? "",
            paymentID ?? "",
            savedToSquare.map { $0 ? "yes" : "no" } ?? "",
            note,
        ]
        append(fields.map(Self.escape).joined(separator: ",") + "\n")
    }

    // MARK: - Writing

    private func append(_ line: String) {
        guard let url = Self.todaysFile() else { return }
        let manager = FileManager.default

        if !manager.fileExists(atPath: url.path) {
            try? Self.header.write(to: url, atomically: true, encoding: .utf8)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// One file per day, named for the kiosk's local date, so the end-of-day
    /// pull is a single predictable filename.
    private static func todaysFile() -> URL? {
        guard let documents = documents() else { return nil }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return documents.appendingPathComponent("\(prefix)\(day.string(from: Date()))\(suffix)")
    }

    private static func documents() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    // MARK: - Reading, for the download server and the staff page

    /// Every day log on the device, newest first.
    func fileNames() -> [String] {
        guard let directory = Self.documents() else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { Self.isLogName($0) }.sorted(by: >)
    }

    /// One day log's bytes. `name` may be a filename or just a date; anything
    /// that is not one of this kiosk's own logs is refused, so a crafted
    /// request cannot reach the rest of the app's container.
    func contents(of name: String) -> Data? {
        guard let file = Self.resolve(name), let directory = Self.documents() else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(file))
    }

    /// What today's file adds up to.
    struct Tally: Equatable {
        let name: String
        /// Every row, paid or not.
        var rows = 0
        /// Paid donations, and what they come to.
        var donations = 0
        var dollars = 0
        var notCompleted = 0
        /// Rows staff still need to look up in the Square Dashboard.
        var unconfirmed = 0
    }

    /// Today's file and its totals, for the staff page — also the quickest
    /// way to tell whether the kiosk is recording at all.
    func todaysTally() -> Tally? {
        guard let url = Self.todaysFile(),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var tally = Tally(name: url.lastPathComponent)
        // Every line but the header is one donation attempt. The first three
        // columns (timestamp, amount, status) never contain a comma.
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = line.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            tally.rows += 1
            switch Status(rawValue: String(fields[2])) {
            case .ok:
                tally.donations += 1
                tally.dollars += Int(fields[1]) ?? 0
            case .unconfirmed:
                tally.unconfirmed += 1
            default:
                tally.notCompleted += 1
            }
        }
        return tally
    }

    /// Turn a requested name into one of our filenames, or nil. Accepts
    /// "kiosk-log-2026-09-17.csv" or bare "2026-09-17".
    static func resolve(_ requested: String) -> String? {
        let name = requested.hasPrefix(prefix) ? requested : "\(prefix)\(requested)\(suffix)"
        return isLogName(name) ? name : nil
    }

    private static let prefix = "kiosk-log-"
    private static let suffix = ".csv"

    /// "kiosk-log-YYYY-MM-DD.csv" and nothing else — no separators, no dots,
    /// nothing that could climb out of the Documents directory.
    private static func isLogName(_ name: String) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
              !name.contains("/"), !name.contains("\\"), !name.contains("..") else { return false }
        let date = name.dropFirst(prefix.count).dropLast(suffix.count)
        return date.count == 10 && date.allSatisfy { $0.isNumber || $0 == "-" }
    }

    // MARK: - Formatting

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
