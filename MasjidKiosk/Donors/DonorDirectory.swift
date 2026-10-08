import Foundation

/// Where a donor's phone number goes, beyond the day's log on the iPad.
@MainActor
protocol DonorDirectory: AnyObject {
    /// Record that `phone` gave `donation`. Returns whether the record was
    /// saved; the kiosk logs the answer and never shows it to the donor.
    func record(phone: PhoneNumber, donation: Donation, paymentID: String?) async -> Bool
}

/// Keeps phone numbers in the day's log only — used in demo mode, or when
/// `KioskConfig.saveDonorsToSquare` is off.
final class LogOnlyDonorDirectory: DonorDirectory {
    func record(phone: PhoneNumber, donation: Donation, paymentID: String?) async -> Bool { false }
}

/// Adds donors to the Square Customer Directory.
///
/// A donor is found by phone number (or created), and each donation is
/// appended to their profile's note, e.g.
/// `2026-10-02 kiosk donation $50 (payment R2B…)`. Square has no way to attach
/// a customer to a payment after it is taken — and the phone number is asked
/// for after — so the note and the day's log are what tie the two together.
final class SquareDonorDirectory: DonorDirectory {

    func record(phone: PhoneNumber, donation: Donation, paymentID: String?) async -> Bool {
        let line = Self.noteLine(donation, paymentID: paymentID)
        do {
            if let existing = try await find(phone.e164) {
                let note = [existing.note, line].compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: "\n")
                try await update(existing.id, note: note, version: existing.version)
            } else {
                try await create(phone.e164, note: line)
            }
            return true
        } catch {
            NSLog("Saving donor to Square failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Customers API

    private struct Customer: Decodable {
        let id: String
        let note: String?
        let version: Int?
    }

    private func find(_ phone: String) async throws -> Customer? {
        struct Body: Encodable {
            struct Query: Encodable {
                struct Filter: Encodable {
                    struct Exact: Encodable { let exact: String }
                    let phoneNumber: Exact
                }
                let filter: Filter
            }
            let query: Query
            let limit: Int
        }
        struct Response: Decodable { let customers: [Customer]? }

        let body = Body(query: .init(filter: .init(phoneNumber: .init(exact: phone))), limit: 1)
        return try await SquareAPI.send("POST", "v2/customers/search", body: body, as: Response.self)
            .customers?.first
    }

    private func create(_ phone: String, note: String) async throws {
        struct Body: Encodable {
            let idempotencyKey: String
            let phoneNumber: String
            let note: String
            let referenceId: String
        }
        struct Response: Decodable { let customer: Customer }
        let body = Body(idempotencyKey: UUID().uuidString, phoneNumber: phone,
                        note: note, referenceId: "masjid-kiosk")
        _ = try await SquareAPI.send("POST", "v2/customers", body: body, as: Response.self)
    }

    private func update(_ id: String, note: String, version: Int?) async throws {
        struct Body: Encodable {
            let note: String
            let version: Int?
        }
        struct Response: Decodable { let customer: Customer }
        // Square caps notes; keep the newest donations if a regular's history
        // outgrows it.
        let capped = String(note.suffix(4_000))
        _ = try await SquareAPI.send("PUT", "v2/customers/\(id)",
                                     body: Body(note: capped, version: version), as: Response.self)
    }

    private static func noteLine(_ donation: Donation, paymentID: String?) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let payment = paymentID.map { " (payment \($0))" } ?? ""
        return "\(day.string(from: Date())) kiosk donation \(donation.formattedAmount)\(payment)"
    }
}
