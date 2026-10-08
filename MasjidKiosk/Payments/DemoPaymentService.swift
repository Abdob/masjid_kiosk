import Foundation

/// Simulated payments for development and for running before Square
/// credentials are configured. Approves every payment after a short delay;
/// no reader is used and no card is charged.
final class DemoPaymentService: PaymentService {

    private var pendingDelay: Task<Void, Error>?

    var isDemo: Bool { true }

    func charge(_ donation: Donation) async -> PaymentOutcome {
        let delay = Task { try await Task.sleep(for: .seconds(3)) }
        pendingDelay = delay
        defer { pendingDelay = nil }

        do {
            try await delay.value
            return .success(paymentID: "DEMO-\(UUID().uuidString.prefix(8))",
                            receiptNote: Loc.t("payment.demoReceipt"))
        } catch {
            return .canceled
        }
    }

    func cancelCurrentPayment() {
        pendingDelay?.cancel()
    }
}
