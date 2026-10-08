import Foundation
import SquareMobilePaymentsSDK

/// Live payments on the Square Stand through Square's Mobile Payments SDK.
///
/// The kiosk hands Square the amount, and Square takes over the screen with
/// its own "tap, insert or swipe" prompt: the card never touches this app's
/// code. Square then reports one of three endings:
///
///     didFinish  → paid
///     didCancel  → the donor (or the kiosk's timeout) backed out
///     didFail    → not paid, as far as the SDK knows
///
/// A failure is not taken at its word. If the connection dropped at the
/// wrong moment the card may have been charged anyway, so the kiosk looks the
/// payment up at Square before telling the donor anything — and before
/// offering a retry that could charge them twice.
final class StandPaymentService: NSObject, PaymentService {

    /// The payment in flight: who is waiting for it, and how to find it again.
    private struct Attempt {
        let id: String
        let reference: String
        let donation: Donation
        let startedAt: Date
        let continuation: CheckedContinuation<PaymentOutcome, Never>
    }

    private var attempt: Attempt?
    private var handle: PaymentHandle?
    private var promptTimeout: Task<Void, Never>?

    var isDemo: Bool { false }

    func charge(_ donation: Donation) async -> PaymentOutcome {
        guard attempt == nil, let presenter = SquareReader.topViewController() else {
            return .failure(message: Loc.t("payment.error.generic"))
        }

        let id = UUID().uuidString
        // Carried on the Square payment, so it can be found again by this
        // kiosk (see `confirm`) or by staff in the Dashboard.
        let reference = "kiosk-\(id.prefix(8))"

        let parameters = PaymentParameters(
            paymentAttemptID: id,
            amountMoney: Money(amount: UInt(donation.amountCents), currency: .USD),
            // Online only: a donation either reaches Square now or isn't taken.
            processingMode: .onlineOnly
        )
        parameters.referenceID = reference
        parameters.note = donation.paymentNote

        // Card only — no cash or typed-in card numbers on a kiosk.
        let prompt = PromptParameters(mode: .default, additionalMethods: AdditionalPaymentMethods())

        return await withCheckedContinuation { continuation in
            attempt = Attempt(id: id, reference: reference, donation: donation,
                              startedAt: Date(), continuation: continuation)
            handle = MobilePaymentsSDK.shared.paymentManager.startPayment(
                parameters, promptParameters: prompt, from: presenter, delegate: self
            )

            if handle == nil {
                // The SDK refused to start. It normally says why through the
                // delegate; this only stops the kiosk waiting forever if not.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    self.finish(id, with: .failure(message: Loc.t("payment.error.generic")))
                }
            } else {
                promptTimeout = Task {
                    try? await Task.sleep(for: .seconds(KioskConfig.cardPromptTimeout))
                    guard !Task.isCancelled else { return }
                    self.cancelCurrentPayment()
                }
            }
        }
    }

    func cancelCurrentPayment() {
        // Once a card is being processed Square won't cancel; the payment
        // then finishes or fails on its own.
        if let handle, handle.isPaymentCancelable {
            _ = handle.cancelPayment()
        }
    }

    // MARK: - Outcome

    /// Hand the outcome to whoever is awaiting `charge`, once.
    private func finish(_ attemptID: String, with outcome: PaymentOutcome) {
        guard let current = attempt, current.id == attemptID else { return }
        promptTimeout?.cancel()
        promptTimeout = nil
        attempt = nil
        handle = nil
        current.continuation.resume(returning: outcome)
    }

    private func didFail(with error: NSError) {
        guard let current = attempt else { return }
        NSLog("Square payment \(current.reference) failed: \(error)")

        let paymentError = error.domain.hasSuffix("PaymentError") ? PaymentError(rawValue: error.code) : nil
        switch paymentError {
        case .notAuthorized, .locationPermissionNeeded, .invalidPaymentParameters,
             .invalidPaymentSource, .paymentAlreadyInProgress, .paymentAttemptIdReused,
             .deviceTimeDoesNotMatchServerTime, .trackingConsentIsPending:
            // Refused before any card was read: nothing can have been taken.
            finish(current.id, with: .failure(message: Loc.t("payment.error.setup")))
        default:
            let message = Loc.t(paymentError == .noNetwork ? "payment.error.noNetwork"
                                                           : "payment.error.generic")
            Task { finish(current.id, with: await confirm(current, failureMessage: message)) }
        }
    }

    /// Ask Square whether a payment the SDK reported as failed went through
    /// after all. Only a clear "no such payment" lets the donor try again.
    private func confirm(_ attempt: Attempt, failureMessage: String) async -> PaymentOutcome {
        struct Response: Decodable {
            struct Payment: Decodable {
                let id: String
                let status: String
                let referenceId: String?
            }
            let payments: [Payment]?
        }

        let begin = ISO8601DateFormatter().string(from: attempt.startedAt.addingTimeInterval(-300))
        let query = [
            URLQueryItem(name: "location_id", value: KioskConfig.squareLocationID),
            URLQueryItem(name: "begin_time", value: begin),
            URLQueryItem(name: "total", value: String(attempt.donation.amountCents)),
            URLQueryItem(name: "limit", value: "100"),
        ]

        for wait in [0, 3, 6, 10] {
            try? await Task.sleep(for: .seconds(wait))
            guard let response = try? await SquareAPI.send("GET", "v2/payments", query: query,
                                                           as: Response.self) else { continue }
            let taken = response.payments?.first {
                $0.referenceId == attempt.reference && ["COMPLETED", "APPROVED"].contains($0.status)
            }
            if let taken {
                return .success(paymentID: taken.id, receiptNote: nil)
            }
            return .failure(message: failureMessage)
        }
        return .unconfirmed(reference: attempt.reference)
    }
}

// The SDK calls its delegate on the main thread.

extension StandPaymentService: PaymentManagerDelegate {

    nonisolated func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
        let paymentID = payment.id
        Task { @MainActor in
            guard let current = self.attempt else { return }
            self.finish(current.id, with: .success(paymentID: paymentID, receiptNote: nil))
        }
    }

    nonisolated func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment,
                                    withError error: Error) {
        let error = error as NSError
        Task { @MainActor in self.didFail(with: error) }
    }

    nonisolated func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
        Task { @MainActor in
            guard let current = self.attempt else { return }
            self.finish(current.id, with: .canceled)
        }
    }
}
