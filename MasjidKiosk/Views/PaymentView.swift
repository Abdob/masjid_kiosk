import SwiftUI

/// Shown while the donor pays on the Square Stand. The charge itself is
/// started and awaited by KioskFlowView. In live mode Square's own card
/// prompt covers this screen, so donors mostly see it in demo mode and for a
/// moment either side of the prompt.
struct PaymentView: View {
    let donation: Donation
    let service: PaymentService

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 110))
                .foregroundStyle(.tint)

            Text(Loc.t("payment.title", donation.formattedAmount))
                .font(.system(size: 48, weight: .bold, design: .rounded))

            Text(Loc.t("payment.message"))
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            ProgressView(Loc.t(service.isDemo ? "payment.progress.demo" : "payment.progress.live"))
                .padding(.top, 8)

            Spacer()

            Button(Loc.t("common.cancel"), role: .cancel) {
                service.cancelCurrentPayment()
            }
            .font(.title3.bold())
            .padding(.bottom, 32)
        }
    }
}

#Preview {
    PaymentView(donation: Donation(dollars: 50), service: DemoPaymentService())
}
