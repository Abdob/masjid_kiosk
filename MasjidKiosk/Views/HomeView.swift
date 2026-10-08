import SwiftUI

/// The idle screen: the masjid's logo, one big Donate button, and the
/// button that switches between English and Arabic.
struct HomeView: View {
    let isDemo: Bool
    /// False in live mode while the Square Stand's reader isn't ready; the
    /// kiosk shows a banner and disables Donate until it is.
    let canTakeDonations: Bool
    /// The language the switch button offers: the one not on screen now.
    let otherLanguage: KioskLanguage
    let onDonate: () -> Void
    let onSwitchLanguage: () -> Void
    /// Fired after 5 quick taps in the hidden top-right corner (staff only).
    let onStaffGesture: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 900
            VStack(spacing: compact ? 24 : 40) {
                Spacer()

                Image("MasjidLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(proxy.size.width * 0.75, 620))
                    .frame(maxHeight: proxy.size.height * (compact ? 0.38 : 0.34))
                    .accessibilityLabel("Masjid Abubakr Alsaddiq — Muslim Community Center")

                VStack(spacing: 10) {
                    Text(Loc.t("home.title"))
                        .font(.system(size: compact ? 40 : 48, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(Loc.t("home.subtitle"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                if !canTakeDonations {
                    Label(Loc.t("home.paused"), systemImage: "exclamationmark.octagon.fill")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 22)
                        .background(.red, in: Capsule())
                }

                Button(action: onDonate) {
                    Label(Loc.t("home.donate"), systemImage: "heart.fill")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .frame(maxWidth: 460)
                        .padding(.vertical, compact ? 6 : 12)
                }
                .buttonStyle(KioskPrimaryButtonStyle())
                .disabled(!canTakeDonations)
                .opacity(canTakeDonations ? 1 : 0.4)
                .padding(.horizontal, 40)

                Spacer()

                if isDemo {
                    Label(Loc.t("home.demoBanner"), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.bold())
                        .padding(10)
                        .background(.yellow.opacity(0.3), in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top) {
                Button(action: onSwitchLanguage) {
                    Label(otherLanguage.name, systemImage: "globe")
                        .font(.title2.bold())
                        .padding(.vertical, 14)
                        .padding(.horizontal, 24)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .padding(24)

                Spacer()

                // The staff page, without exposing anything to donors.
                HiddenCornerTapTarget(action: onStaffGesture)
            }
            // Both stay in the same physical corners in either language.
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// Invisible staff-only tap target for a screen corner: 5 taps within
/// 4 seconds fires `action`; slower taps restart the count.
private struct HiddenCornerTapTarget: View {
    let action: () -> Void

    @State private var tapCount = 0
    @State private var lastTap = Date.distantPast

    var body: some View {
        Color.clear
            .frame(width: 88, height: 88)
            .contentShape(Rectangle())
            .onTapGesture {
                let now = Date()
                tapCount = now.timeIntervalSince(lastTap) < 4 ? tapCount + 1 : 1
                lastTap = now
                if tapCount >= 5 {
                    tapCount = 0
                    action()
                }
            }
    }
}

#Preview("Ready") {
    HomeView(isDemo: true, canTakeDonations: true, otherLanguage: .arabic,
             onDonate: {}, onSwitchLanguage: {}, onStaffGesture: {})
}

#Preview("Reader not ready") {
    HomeView(isDemo: false, canTakeDonations: false, otherLanguage: .arabic,
             onDonate: {}, onSwitchLanguage: {}, onStaffGesture: {})
}
