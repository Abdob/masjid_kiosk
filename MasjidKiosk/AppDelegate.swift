import SquareMobilePaymentsSDK
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Kiosk: never let the screen sleep. Re-assert whenever the app
        // becomes active again — iOS can drop the override across a
        // lock/unlock cycle.
        application.isIdleTimerDisabled = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }

        // Square's SDK must be initialized here, before anything else uses
        // it. In demo mode it is never started.
        if KioskConfig.isSquareConfigured {
            MobilePaymentsSDK.initialize(
                applicationLaunchOptions: launchOptions,
                squareApplicationID: KioskConfig.squareApplicationID
            )
            SquareReader.shared.start()
        }

        // Start answering log downloads. The listener only lives while the
        // app is in the foreground, which for a Guided Access kiosk is always.
        KioskLogServer.shared.start()

        return true
    }
}
