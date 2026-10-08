import SwiftUI

/// Large card-shaped button, used for the amount presets.
struct KioskCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Full-width call-to-action button.
struct KioskPrimaryButtonStyle: ButtonStyle {
    var prominent = true
    /// Shorter, for screens that have to fit a keypad into an iPad's
    /// landscape height.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .title3.bold() : .title2.bold())
            .padding(.vertical, compact ? 13 : 20)
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.12)))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Big square-ish keypad key.
struct KioskKeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The logo's palette, for accents beyond the app-wide blue tint.
enum Brand {
    static let blue = Color(red: 0.231, green: 0.380, blue: 0.675)   // #3B61AC
    static let coral = Color(red: 0.980, green: 0.353, blue: 0.353)  // #FA5A5A
    static let gold = Color(red: 0.969, green: 0.690, blue: 0.239)   // #F7B03D
}

/// The 3×4 number pad shared by the amount and phone screens.
struct Keypad: View {
    var compact = false
    let onDigit: (Int) -> Void
    let onClear: () -> Void
    let onDelete: () -> Void
    /// Fired on every tap so the flow can restart its inactivity timeout.
    var onInteraction: () -> Void = {}

    var body: some View {
        let spacing: CGFloat = compact ? 10 : 14
        VStack(spacing: spacing) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { digit in
                        key(label: "\(digit)") { onDigit(digit) }
                    }
                }
            }
            HStack(spacing: spacing) {
                key(label: "C", action: onClear)
                key(label: "0") { onDigit(0) }
                key(systemImage: "delete.left", action: onDelete)
            }
        }
        // A number pad reads 1-2-3 from the left in Arabic too.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func key(label: String? = nil, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            onInteraction()
            action()
        } label: {
            Group {
                if let label {
                    Text(label)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .font(.system(size: compact ? 28 : 34, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: compact ? 56 : 74)
        }
        .buttonStyle(KioskKeypadButtonStyle())
    }
}
