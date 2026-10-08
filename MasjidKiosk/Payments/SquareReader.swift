import CoreBluetooth
import CoreLocation
import SquareMobilePaymentsSDK
import UIKit

/// The kiosk's connection to Square's Mobile Payments SDK: signing the SDK in
/// to the masjid's account, and watching the Square Stand's card reader.
///
/// The Stand needs no pairing. Once the SDK is signed in and the iPad is
/// docked, the Stand's reader shows up here on its own. The kiosk only takes
/// donations while a reader reports itself ready.
@MainActor
final class SquareReader: NSObject, ObservableObject {
    static let shared = SquareReader()

    enum SignIn: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
    }

    /// One reader as the staff page shows it.
    struct Reader: Identifiable, Equatable {
        let id: UInt
        let name: String
        let status: String
        let isReady: Bool
    }

    // Each change is logged: "why is the kiosk paused" is otherwise only
    // answerable from the staff page.
    @Published private(set) var signIn: SignIn = .signedOut {
        didSet { if signIn != oldValue { NSLog("Square sign-in: \(signIn)") } }
    }
    @Published private(set) var readers: [Reader] = [] {
        didSet {
            guard readers != oldValue else { return }
            let list = readers.map { "\($0.name) — \($0.status)" }.joined(separator: "; ")
            NSLog("Square readers: \(list.isEmpty ? "none" : list)")
        }
    }
    /// False when staff have refused location access, which Square requires
    /// for every payment.
    @Published private(set) var isLocationAllowed = true {
        didSet { if isLocationAllowed != oldValue { NSLog("Location allowed: \(isLocationAllowed)") } }
    }

    /// True when a donation can be taken right now.
    var isReady: Bool {
        signIn == .signedIn && isLocationAllowed && readers.contains { $0.isReady }
    }

    private var hasStarted = false
    private var retryTask: Task<Void, Never>?
    private let locationManager = CLLocationManager()
    private var bluetoothManager: CBCentralManager?

    private var sdk: SDKManager { MobilePaymentsSDK.shared }

    /// Call once at launch, after `MobilePaymentsSDK.initialize`. Asks for the
    /// permissions Square needs, signs in, and starts watching readers.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        sdk.authorizationManager.add(self)
        sdk.readerManager.add(self)

        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        if CBManager.authorization == .notDetermined {
            // Creating the manager is what makes iOS ask.
            bluetoothManager = CBCentralManager(delegate: self, queue: .main)
        }

        refreshLocationPermission()
        refreshReaders()
        authorize()
    }

    /// Sign the SDK in to the configured account and location. The SDK
    /// remembers the sign-in across launches, so this is usually a no-op.
    func authorize() {
        guard hasStarted else { return }
        retryTask?.cancel()
        let manager = sdk.authorizationManager

        switch manager.state {
        case .authorized:
            // Signed in from an earlier launch — but KioskConfig may have
            // been pointed at another location since.
            if let location = manager.location, location.id != KioskConfig.squareLocationID {
                signIn = .signingIn
                manager.deauthorize { [weak self] in
                    Task { @MainActor in self?.authorize() }
                }
            } else {
                signIn = .signedIn
            }
        case .authorizing:
            signIn = .signingIn
        default:
            signIn = .signingIn
            manager.authorize(
                withAccessToken: KioskConfig.squareAccessToken,
                locationID: KioskConfig.squareLocationID
            ) { [weak self] error in
                Task { @MainActor in self?.didAuthorize(error) }
            }
        }
    }

    /// Square's own reader screen: reader details, firmware, pairing a
    /// separate contactless reader.
    func presentReaderSettings() {
        guard hasStarted, let presenter = Self.topViewController() else { return }
        sdk.settingsManager.presentSettings(with: presenter) { error in
            if let error { NSLog("Square reader settings: \(error.localizedDescription)") }
        }
    }

    /// The view controller on top of everything, for the Square screens that
    /// need one to present from.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Private

    private func didAuthorize(_ error: Error?) {
        guard let error else {
            signIn = .signedIn
            refreshReaders()
            return
        }
        NSLog("Square sign-in failed: \(error)")
        signIn = .failed(error.localizedDescription)

        // A kiosk often powers up before the Wi-Fi does; keep trying.
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.authorize()
        }
    }

    private func refreshReaders() {
        readers = sdk.readerManager.readers.map { info in
            Reader(id: info.id,
                   name: info.name,
                   status: Self.describe(info.statusInfo),
                   isReady: info.statusInfo.status == .ready)
        }
    }

    private func refreshLocationPermission() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted: isLocationAllowed = false
        default: isLocationAllowed = true
        }
    }

    private static func describe(_ info: ReaderStatusInfo) -> String {
        switch info.status {
        case .ready: return "Ready"
        case .connectingToDevice: return "Connecting…"
        case .connectingToSquare: return "Connecting to Square…"
        case .faulty: return "Faulty — the reader may need replacing"
        case .readerUnavailable: return info.unavailableReasonInfo?.title ?? "Unavailable"
        @unknown default: return "Unknown"
        }
    }
}

// The SDK calls all of these on the main thread.

extension SquareReader: AuthorizationStateObserver {
    nonisolated func authorizationStateDidChange(_ authorizationState: AuthorizationState) {
        Task { @MainActor in
            switch authorizationState {
            case .authorized: self.signIn = .signedIn
            case .authorizing: self.signIn = .signingIn
            default:
                // Keep the reason on screen if a sign-in just failed.
                if case .failed = self.signIn { break }
                self.signIn = .signedOut
            }
            self.refreshReaders()
        }
    }
}

extension SquareReader: ReaderObserver {
    nonisolated func readerWasAdded(_ readerInfo: ReaderInfo) {
        Task { @MainActor in self.refreshReaders() }
    }

    nonisolated func readerWasRemoved(_ readerInfo: ReaderInfo) {
        Task { @MainActor in self.refreshReaders() }
    }

    nonisolated func readerDidChange(_ readerInfo: ReaderInfo, change: ReaderChange) {
        Task { @MainActor in self.refreshReaders() }
    }
}

extension SquareReader: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refreshLocationPermission() }
    }
}

extension SquareReader: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}
}
