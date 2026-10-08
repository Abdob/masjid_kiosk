import SwiftUI

/// After paying: an optional phone number so the masjid can keep a record of
/// the donation. Done needs a full 10-digit number; Skip moves straight on.
struct PhoneEntryView: View {
    let donation: Donation
    /// The number, or nil for Skip.
    let onFinish: (PhoneNumber?) -> Void
    /// Fired on every tap so the flow can restart its inactivity timeout.
    let onInteraction: () -> Void

    @State private var phone = PhoneNumber()

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 900
            content(compact: compact)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 12 : 24) {
            Label(Loc.t("phone.thanks", donation.formattedAmount), systemImage: "checkmark.circle.fill")
                .font(compact ? .headline.bold() : .title3.bold())
                .foregroundStyle(.green)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.green.opacity(0.12), in: Capsule())
                .padding(.top, compact ? 12 : 32)

            VStack(spacing: 8) {
                Text(Loc.t("phone.title"))
                    .font(compact ? .title2.bold() : .largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(Loc.t("phone.subtitle"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Text(phone.digits.isEmpty ? Loc.t("phone.placeholder") : phone.formatted)
                .font(.system(size: compact ? 44 : 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(phone.digits.isEmpty ? Color(.tertiaryLabel) : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 6 : 12)
                // Keep "(555) 123-4567" in that order in Arabic too.
                .environment(\.layoutDirection, .leftToRight)

            Keypad(
                compact: compact,
                onDigit: { phone.append($0) },
                onClear: { phone.clear() },
                onDelete: { phone.deleteLast() },
                onInteraction: onInteraction
            )
            .padding(.horizontal, compact ? 24 : 40)

            HStack(spacing: 16) {
                Button {
                    onFinish(nil)
                } label: {
                    Text(Loc.t("phone.skip")).frame(maxWidth: .infinity)
                }
                .buttonStyle(KioskPrimaryButtonStyle(prominent: false, compact: compact))

                Button {
                    onFinish(phone)
                } label: {
                    Text(Loc.t("phone.done")).frame(maxWidth: .infinity)
                }
                .buttonStyle(KioskPrimaryButtonStyle(compact: compact))
                .disabled(!phone.isComplete)
                .opacity(phone.isComplete ? 1 : 0.4)
            }
            .padding(.horizontal, compact ? 24 : 40)
            .padding(.bottom, compact ? 10 : 24)
        }
    }
}

#Preview {
    PhoneEntryView(donation: Donation(dollars: 50), onFinish: { _ in }, onInteraction: {})
}
