import Foundation

/// Central configuration for the kiosk.
///
/// To go live, replace the three `REPLACE_WITH_…` values with the masjid's
/// Square credentials (see README.md) and dock the iPad in the Square Stand.
/// Until then the app runs in Demo Mode: the full flow works, but no reader
/// is used and no card is charged.
enum KioskConfig {

    // MARK: Square credentials

    /// The application ID of the masjid's Square application
    /// (Developer Dashboard → your application → Credentials). A production
    /// ID starts with "sq0idp-"; a "sandbox-" ID puts the whole kiosk in
    /// Square's sandbox, where real readers don't work.
    static let squareApplicationID = "sq0idp-Czmg_yWKiU756ycD7-FRug"

    /// A production access token for the masjid's Square account (same
    /// Credentials page). It needs the MERCHANT_PROFILE_READ, PAYMENTS_WRITE,
    /// PAYMENTS_WRITE_IN_PERSON, PAYMENTS_READ and CUSTOMERS scopes; a
    /// personal access token has all of them.
    static let squareAccessToken = "EAAAl_iWL3NKJdpF6X4I3Mcq2LgL3Nv5AXgI6M61fl0vENZyEvArznCLfTuS3yKe"

    /// The community center's location (Developer Dashboard → Locations).
    static let squareLocationID = "L2F9X7KBN2VF1"

    /// Square's REST API, matching the application ID's environment.
    static var squareBaseURL: URL {
        squareApplicationID.hasPrefix("sandbox-")
            ? URL(string: "https://connect.squareupsandbox.com")!
            : URL(string: "https://connect.squareup.com")!
    }

    /// The Square API version every request is pinned to.
    static let squareAPIVersion = "2025-01-23"

    /// True once real credentials have been filled in above.
    static var isSquareConfigured: Bool {
        ![squareApplicationID, squareAccessToken, squareLocationID]
            .contains { $0.hasPrefix("REPLACE_WITH_") || $0.isEmpty }
    }

    // MARK: Square Stand

    /// Seconds Square's "tap, insert or swipe" screen waits for a card
    /// before the kiosk cancels the payment and returns home.
    static let cardPromptTimeout: TimeInterval = 180

    // MARK: Donor records

    /// Besides the day's log on the iPad, add every phone number a donor
    /// leaves to the Square Customer Directory, with the donation noted on
    /// their profile. Turn off to keep phone numbers on the iPad only.
    static let saveDonorsToSquare = true

    // MARK: Amounts (whole dollars)

    /// Quick-pick buttons on the amount screen.
    static let presetDollars = [10, 20, 50, 100]

    static let minimumDollars = 1
    static let maximumDollars = 10_000

    // MARK: Kiosk timeouts

    /// Seconds of inactivity on the amount screen before returning home.
    /// Each tap restarts the countdown.
    static let amountEntryIdleTimeout: TimeInterval = 60

    /// Seconds of inactivity on the phone-number screen before it is treated
    /// as "Skip". The donation is already made, so nothing is lost.
    static let phoneEntryIdleTimeout: TimeInterval = 45

    /// Seconds the thank-you / failure screen stays up before returning home.
    static let resultScreenTimeout: TimeInterval = 10

    // MARK: Log download server

    /// The kiosk serves its day logs over HTTP on the masjid's network, so
    /// they can be collected with `curl` from any machine while the iPad
    /// stays locked in Guided Access. See README.md.
    static let isLogServerEnabled = true

    /// Port the kiosk listens on. Anything above 1024 is fine.
    static let logServerPort: UInt16 = 8080

    /// HTTP basic-auth for the download. The log holds donors' phone numbers,
    /// and this travels the network in the clear — keep the kiosk off any
    /// Wi-Fi the public can join.
    static let logServerUser = "admin"
    static let logServerPassword = "@ntiochMasjid2016"
}
