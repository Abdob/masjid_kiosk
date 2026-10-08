import SwiftUI

/// Choose a donation: one of the preset amounts, or any whole-dollar amount
/// typed on the keypad.
struct AmountEntryView: View {
    let onCancel: () -> Void
    let onConfirm: (Int) -> Void
    /// Fired on every tap so the flow can restart its inactivity timeout.
    let onInteraction: () -> Void

    @State private var dollars = 0
    /// True while `dollars` came from a preset button: the next keypad digit
    /// starts a fresh amount instead of appending to "50" → "505".
    @State private var isPreset = false

    private var isValid: Bool {
        (KioskConfig.minimumDollars...KioskConfig.maximumDollars).contains(dollars)
    }

    var body: some View {
        // An iPad in landscape leaves about 820pt of height; below the
        // threshold everything tightens rather than spilling off the top.
        GeometryReader { proxy in
            let compact = proxy.size.height < 900
            content(compact: compact)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 12 : 24) {
            HStack {
                Button(Loc.t("common.cancel"), action: onCancel)
                    .font(.title3.bold())
                    .padding()
                Spacer()
            }

            Text(Loc.t("amount.title"))
                .font(compact ? .title2.bold() : .largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            presets(compact: compact)
                .padding(.horizontal, compact ? 24 : 40)

            VStack(spacing: compact ? 2 : 6) {
                Text(Donation.format(dollars))
                    .font(.system(size: compact ? 56 : 80, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isValid ? Color.primary : Color.secondary)
                Text(Loc.t("amount.other"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Keypad(
                compact: compact,
                onDigit: append,
                onClear: { dollars = 0; isPreset = false },
                onDelete: { dollars = isPreset ? 0 : dollars / 10; isPreset = false },
                onInteraction: onInteraction
            )
            .padding(.horizontal, compact ? 24 : 40)

            Button {
                onConfirm(dollars)
            } label: {
                Text(isValid ? Loc.t("amount.cta.donate", Donation.format(dollars)) : Loc.t("amount.cta.enter"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(KioskPrimaryButtonStyle(compact: compact))
            .disabled(!isValid)
            .padding(.horizontal, compact ? 24 : 40)
            .padding(.bottom, compact ? 10 : 24)
        }
    }

    private func presets(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            ForEach(KioskConfig.presetDollars, id: \.self) { amount in
                let selected = isPreset && dollars == amount
                Button {
                    onInteraction()
                    dollars = amount
                    isPreset = true
                } label: {
                    Text(Donation.format(amount))
                        .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? Color.white : Color.accentColor)
                        .frame(maxWidth: .infinity, minHeight: compact ? 60 : 84)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selected ? AnyShapeStyle(Color.accentColor)
                                               : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func append(_ digit: Int) {
        let base = isPreset ? 0 : dollars
        isPreset = false
        guard !(base == 0 && digit == 0) else { dollars = 0; return }
        let next = base * 10 + digit
        guard next <= KioskConfig.maximumDollars else { return }
        dollars = next
    }
}

#Preview {
    AmountEntryView(onCancel: {}, onConfirm: { _ in }, onInteraction: {})
}
