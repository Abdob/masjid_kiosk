import SwiftUI

/// The closing screen: thank you, or what went wrong. Auto-returns home via
/// KioskFlowView's idle timer; donors can also dismiss it right away.
struct ResultView: View {
    let donation: Donation
    let result: KioskResult
    let onRetry: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            switch result {
            case .thanks(let phoneGiven):
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(Brand.coral)
                Text(Loc.t("thanks.title"))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(Loc.t("thanks.amount", donation.formattedAmount))
                    .font(.title2)
                    .foregroundStyle(.secondary)
                if phoneGiven {
                    Text(Loc.t("thanks.saved"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text(Loc.t("thanks.dua"))
                    .font(.title2.bold())
                    .foregroundStyle(.tint)
                    .padding(.top, 8)

            case .failure(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.red)
                Text(Loc.t("failure.title"))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)

            case .unconfirmed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.orange)
                Text(Loc.t("unconfirmed.title"))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(Loc.t("unconfirmed.message", donation.formattedAmount))
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 14) {
                if showsRetry {
                    Button(action: onRetry) {
                        Text(Loc.t("common.tryAgain")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KioskPrimaryButtonStyle())
                }
                Button(action: onDone) {
                    Text(Loc.t("common.done")).frame(maxWidth: .infinity)
                }
                .buttonStyle(KioskPrimaryButtonStyle(prominent: !showsRetry))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    /// Retry only for a payment that definitely failed. An unconfirmed one
    /// may have been charged, so it must never offer a second charge.
    private var showsRetry: Bool {
        if case .failure = result { return true }
        return false
    }
}

#Preview("Thanks") {
    ResultView(donation: Donation(dollars: 50), result: .thanks(phoneGiven: true), onRetry: {}, onDone: {})
}

#Preview("Failure") {
    ResultView(donation: Donation(dollars: 50), result: .failure(message: "The card was declined."),
               onRetry: {}, onDone: {})
}
