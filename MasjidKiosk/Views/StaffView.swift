import SwiftUI

/// Hidden staff page (top-right corner, 5 taps): today's totals, the iPad's
/// address, the Square Stand's card reader, and where to download the day's
/// donation log.
struct StaffView: View {
    let isDemo: Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reader = SquareReader.shared
    @State private var tally: KioskLog.Tally?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack {
                    Label("Staff", systemImage: "wrench.and.screwdriver.fill")
                        .font(.title.bold())
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.title3.bold())
                }

                todaySection
                readerSection
                logSection
            }
            .padding(40)
        }
        .background(Color(.systemGroupedBackground))
        .task { tally = await KioskLog.shared.todaysTally() }
    }

    // MARK: - Today

    private var todaySection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today").font(.title2.bold())

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(Donation.format(tally?.dollars ?? 0))
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    let count = tally?.donations ?? 0
                    Text("from \(count) donation\(count == 1 ? "" : "s")")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                if let tally, tally.notCompleted > 0 {
                    row("Not completed", "\(tally.notCompleted)")
                }
                if let tally, tally.unconfirmed > 0 {
                    Text("\(tally.unconfirmed) unconfirmed — check the Square Dashboard; these are not in the total.")
                        .foregroundStyle(.orange).font(.headline)
                }

                row("iPad address", KioskLogServer.wifiAddress() ?? "none — check the Wi-Fi")
            }
        }
    }

    // MARK: - Card reader

    private var readerSection: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Square Stand").font(.title2.bold())

                if isDemo {
                    Text("Demo mode — no Square credentials in KioskConfig.swift, so no card reader is used. Fill them in to go live.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    row("Square account", signInText)
                    row("Location", KioskConfig.squareLocationID)

                    if reader.readers.isEmpty {
                        row("Card reader", "none found")
                        Text("Dock the iPad in the Square Stand and check the Stand has power.")
                            .foregroundStyle(.orange).font(.headline)
                    }
                    ForEach(reader.readers) { found in
                        row(found.name, found.status)
                    }

                    if !reader.isLocationAllowed {
                        Text("Location access is off. Square requires it for every payment: turn it on for this app in the iPad's Settings.")
                            .foregroundStyle(.red).font(.headline)
                    }

                    HStack(spacing: 16) {
                        Button {
                            reader.presentReaderSettings()
                        } label: {
                            Label("Reader settings", systemImage: "creditcard.and.123")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(KioskPrimaryButtonStyle(compact: true))
                        .disabled(reader.signIn != .signedIn)

                        if case .failed = reader.signIn {
                            Button {
                                reader.authorize()
                            } label: {
                                Text("Try again").frame(maxWidth: 160)
                            }
                            .buttonStyle(KioskPrimaryButtonStyle(prominent: false, compact: true))
                        }
                    }
                }
            }
        }
    }

    private var signInText: String {
        switch reader.signIn {
        case .signedIn: return "signed in"
        case .signingIn: return "signing in…"
        case .signedOut: return "not signed in"
        case .failed(let reason): return "sign-in failed — \(reason)"
        }
    }

    // MARK: - Log

    private var logSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Donation log").font(.title2.bold())
                row("Today's file", tally?.name ?? "nothing recorded yet today")
                Text("Download from any computer on this network")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(KioskLogServer.downloadURL() ?? "No Wi-Fi address — check the network")
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .minimumScaleFactor(0.5)
                Text("sign in as  \(KioskConfig.logServerUser)  with the log password")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
            Text(value)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    StaffView(isDemo: true)
}
