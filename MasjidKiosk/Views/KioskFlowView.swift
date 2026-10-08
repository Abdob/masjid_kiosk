import SwiftUI

/// How a donation ended, for the closing screen.
enum KioskResult: Equatable {
    case thanks(phoneGiven: Bool)   // paid
    case failure(message: String)   // not paid; nothing taken
    case unconfirmed                // can't tell whether it was paid — see staff
}

/// The kiosk's screens, modeled as one state machine:
/// home → amount → paying on the card reader → phone number → thank you.
enum KioskStep: Equatable {
    case home
    case enterAmount
    case paying(Donation)
    case enterPhone(Donation, paymentID: String?)
    case result(Donation, KioskResult)
}

/// Root view: owns the current step, the idle timeout that returns the kiosk
/// to the home screen, and writing every donation to the day's log.
struct KioskFlowView: View {
    let service: PaymentService
    let donorDirectory: DonorDirectory

    @ObservedObject private var reader = SquareReader.shared
    @State private var step: KioskStep = KioskFlowView.initialStep
    @State private var language = KioskFlowView.initialLanguage
    @State private var idleReturnTask: Task<Void, Never>?
    @State private var showingStaffPage = false
    @State private var hasRunLaunchHooks = false

    /// Debug-only hook so screens can be launched directly for screenshot
    /// verification: `-kioskStartStep amount|paying|phone|thanks|failure|unconfirmed`.
    private static var initialStep: KioskStep {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-kioskStartStep"),
           arguments.indices.contains(flagIndex + 1) {
            let sample = Donation(dollars: 50)
            switch arguments[flagIndex + 1] {
            case "amount": return .enterAmount
            case "paying": return .paying(sample)
            case "phone": return .enterPhone(sample, paymentID: "DEMO")
            case "thanks": return .result(sample, .thanks(phoneGiven: true))
            case "failure": return .result(sample, .failure(message: "The card was declined."))
            case "unconfirmed": return .result(sample, .unconfirmed)
            default: break
            }
        }
        #endif
        return .home
    }

    /// Debug-only companion to `-kioskStartStep`: `-kioskLanguage ar`.
    private static var initialLanguage: KioskLanguage {
        var language = KioskLanguage.standard
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-kioskLanguage"),
           arguments.indices.contains(flagIndex + 1) {
            language = KioskLanguage(rawValue: arguments[flagIndex + 1]) ?? language
        }
        #endif
        Loc.language = language
        return language
    }

    /// Live mode needs Square signed in and the Stand's reader ready.
    private var canTakeDonations: Bool {
        service.isDemo || reader.isReady
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            screen
                .environment(\.layoutDirection, language.layoutDirection)
                // The screens read their wording through Loc, which SwiftUI
                // can't observe; a new identity redraws them in the new language.
                .id(language)
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            if !hasRunLaunchHooks {
                hasRunLaunchHooks = true
                // onChange only fires on changes, not the initial value; this
                // matters when a debug -kioskStartStep launches a timed screen.
                scheduleIdleReturn(for: step)
            }
        }
        .onChange(of: step) { newStep in
            // Each donor starts in the standard language.
            if newStep == .home { setLanguage(.standard) }
            scheduleIdleReturn(for: newStep)
        }
        .sheet(isPresented: $showingStaffPage) {
            StaffView(isDemo: service.isDemo)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .home:
            HomeView(
                isDemo: service.isDemo,
                canTakeDonations: canTakeDonations,
                otherLanguage: language.other,
                onDonate: { step = .enterAmount },
                onSwitchLanguage: switchLanguage,
                onStaffGesture: { showingStaffPage = true }
            )

        case .enterAmount:
            AmountEntryView(
                onCancel: { step = .home },
                onConfirm: { dollars in beginPayment(Donation(dollars: dollars)) },
                onInteraction: { scheduleIdleReturn(for: step) }
            )

        case .paying(let donation):
            PaymentView(donation: donation, service: service)

        case .enterPhone(let donation, _):
            PhoneEntryView(
                donation: donation,
                onFinish: finishPhoneStep,
                onInteraction: { scheduleIdleReturn(for: step) }
            )

        case .result(let donation, let result):
            ResultView(
                donation: donation,
                result: result,
                onRetry: { beginPayment(donation) },
                onDone: { step = .home }
            )
        }
    }

    private func setLanguage(_ new: KioskLanguage) {
        Loc.language = new
        language = new
    }

    /// The donor tapped the language button on the home screen. If they then
    /// walk away, the kiosk goes back to the standard language by itself.
    private func switchLanguage() {
        setLanguage(language.other)
        idleReturnTask?.cancel()
        idleReturnTask = Task {
            try? await Task.sleep(for: .seconds(KioskConfig.amountEntryIdleTimeout))
            guard !Task.isCancelled, step == .home else { return }
            setLanguage(.standard)
        }
    }

    /// Runs the one charge for a donation. The charge is owned by the flow,
    /// not by PaymentView's lifecycle, so nothing can start it twice.
    private func beginPayment(_ donation: Donation) {
        step = .paying(donation)
        Task {
            switch await service.charge(donation) {
            case .canceled:
                step = .home
            case .failure(let message):
                step = .result(donation, .failure(message: message))
                await KioskLog.shared.record(donation, status: .declined, note: message)
            case .unconfirmed(let reference):
                step = .result(donation, .unconfirmed)
                await KioskLog.shared.record(
                    donation, status: .unconfirmed,
                    note: "couldn't confirm payment with reference \(reference) — check Square Dashboard")
            case .success(let paymentID, _):
                step = .enterPhone(donation, paymentID: paymentID)
            }
        }
    }

    /// The donor tapped Done (with a number) or Skip (nil), or walked away.
    /// Every paid donation is logged here, exactly once: the guard on `step`
    /// makes a Done racing the idle timeout a no-op the second time.
    private func finishPhoneStep(_ phone: PhoneNumber?) {
        guard case .enterPhone(let donation, let paymentID) = step else { return }
        step = .result(donation, .thanks(phoneGiven: phone != nil))

        Task {
            var saved: Bool?
            if let phone {
                saved = await donorDirectory.record(phone: phone, donation: donation, paymentID: paymentID)
            }
            await KioskLog.shared.record(donation, status: .ok, phone: phone,
                                         paymentID: paymentID, savedToSquare: saved)
        }
    }

    /// Kiosks get abandoned mid-flow; quietly move on. The phone screen
    /// times out as "Skip" so the donation still gets logged. Paying is never
    /// interrupted here — the payment service's own timeout ends an abandoned
    /// card prompt.
    private func scheduleIdleReturn(for step: KioskStep) {
        idleReturnTask?.cancel()
        idleReturnTask = nil

        let timeout: TimeInterval
        switch step {
        case .home, .paying:
            return
        case .enterAmount:
            timeout = KioskConfig.amountEntryIdleTimeout
        case .enterPhone:
            timeout = KioskConfig.phoneEntryIdleTimeout
        case .result:
            timeout = KioskConfig.resultScreenTimeout
        }

        idleReturnTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            if case .enterPhone = self.step {
                finishPhoneStep(nil)
            } else {
                self.step = .home
            }
        }
    }
}

#Preview {
    KioskFlowView(service: DemoPaymentService(), donorDirectory: LogOnlyDonorDirectory())
}
