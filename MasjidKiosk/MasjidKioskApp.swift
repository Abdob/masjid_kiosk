import SwiftUI

@main
struct MasjidKioskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Picks the live backends when Square credentials are configured,
    /// otherwise falls back to on-device simulators so the full flow runs in
    /// the simulator with nothing wired up.
    @MainActor
    private static func makeServices() -> (PaymentService, DonorDirectory) {
        if KioskConfig.isSquareConfigured {
            let directory: DonorDirectory = KioskConfig.saveDonorsToSquare
                ? SquareDonorDirectory()
                : LogOnlyDonorDirectory()
            return (StandPaymentService(), directory)
        }
        return (DemoPaymentService(), LogOnlyDonorDirectory())
    }

    var body: some Scene {
        let (payment, directory) = Self.makeServices()
        return WindowGroup {
            KioskFlowView(service: payment, donorDirectory: directory)
                .statusBarHidden(true)
                .preferredColorScheme(.light)
        }
    }
}
