import Foundation

/// Result of asking the donor to pay.
enum PaymentOutcome: Equatable {
    /// Money was taken. `paymentID` is Square's payment ID, for the log.
    case success(paymentID: String?, receiptNote: String?)
    /// No money was taken.
    case failure(message: String)
    /// The donor (or the kiosk) backed out before paying.
    case canceled
    /// The kiosk cannot say whether the card was charged. Never offer a retry
    /// on this — it could charge twice. `reference` is the reference ID the
    /// payment carries at Square, if it exists.
    case unconfirmed(reference: String)
}

/// Abstraction over the payment backend so the UI doesn't care whether it's
/// talking to the Square Stand or the built-in demo simulator.
@MainActor
protocol PaymentService: AnyObject {
    /// True when running without real Square credentials.
    var isDemo: Bool { get }

    /// Ask the donor to pay on the card reader and wait for the outcome.
    func charge(_ donation: Donation) async -> PaymentOutcome

    /// Abort the in-flight `charge`. If the donor has already paid, the
    /// charge still returns `.success` — a completed payment is never lost.
    func cancelCurrentPayment()
}
