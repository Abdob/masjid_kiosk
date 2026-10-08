# Masjid Donation Kiosk

A single-purpose iPad app for Masjid Abubakr Alsaddiq's donation station. It
runs on an iPad (A16) docked in a **Square Stand** and takes card payments on
the Stand's built-in reader through Square's Mobile Payments SDK. Donors:

1. Tap **Donate**.
2. Pick **$10 / $20 / $50 / $100**, or type any whole-dollar amount
   ($1–$10,000).
3. Pay on the Stand's card reader (tap, insert, or swipe).
4. Optionally enter a phone number on the iPad: **Done** saves it, **Skip**
   moves on. Walking away counts as Skip.
5. See a thank-you screen, after which the kiosk resets itself.

The app's own code never handles card data. It hands Square's SDK the
amount, Square shows its own card prompt over the app and reads the card on
the Stand, and the SDK reports back whether the payment went through.

## Run it now (demo mode)

Open `MasjidKiosk.xcodeproj` and run it on an iPad simulator or the iPad.
While no Square credentials are configured, the app runs in **demo mode**:
every payment "approves" after 3 seconds and a yellow banner says nothing is
being charged.

## Go live

1. **Credentials.** Create an application at
   <https://developer.squareup.com/apps>, signed in as the **masjid's** Square
   account. In [`MasjidKiosk/KioskConfig.swift`](MasjidKiosk/KioskConfig.swift),
   fill in:
   - `squareApplicationID`: the production application ID (Credentials tab,
     starts with `sq0idp-`).
   - `squareAccessToken`: the production access token (same tab).
   - `squareLocationID`: the community center's location (Locations tab).
2. **Application signature.** Square refuses production payments from an app
   it doesn't know. In the Developer Dashboard, open the application →
   **Mobile Payments SDK** → **Add Signature**, and enter the app's bundle ID
   (`com.abdo.masjidabubakar.kiosk`) and your Apple Team ID. Changing either
   one later needs a new signature.
3. **Install on the iPad.** Select your signing team on the *MasjidKiosk*
   target and run it on the device. On first launch, allow **Location** and
   **Bluetooth** when asked; Square requires both.
4. **Dock the iPad in the Square Stand.** There is nothing to pair: the app
   signs in to Square by itself and the Stand's reader appears within a few
   seconds. The **Donate** button stays disabled, with a red banner, until
   Square is signed in and a reader is ready.
5. **Check it.** Tap the **top-right corner 5 times within 4 seconds** to open
   the staff page. It shows the sign-in state and each reader's status, and
   **Reader settings** opens Square's own reader screen. Then make a $1
   donation with a real card and refund it from the Square Dashboard.

Real readers only work in production. A `sandbox-` application ID puts the
kiosk in Square's sandbox, which needs Square's separate mock reader and
isn't set up in this project.

### Square's conditions

- **The kiosk must be attended.** Square prohibits the Mobile Payments SDK on
  unattended kiosks: it must be out of reach outside opening hours, in sight
  of staff, and staff must be able to help donors.
- **Access token.** Square's guidance is to sign in with OAuth and not to
  ship a personal access token in an app. This kiosk builds the token in, as
  it is installed by hand on one iPad the masjid owns. See *Kiosk hardening*.
- **Receipts.** Square expects card-present apps to offer the buyer a
  receipt. The SDK doesn't send one and this app doesn't either yet.
- **App Store.** Installing from Xcode works as is. Distributing through the
  App Store or TestFlight needs Square to authorize the app for the Stand
  with Apple first, which can take weeks.

### Settings worth knowing (all in `KioskConfig.swift`)

| setting | default | what it does |
| --- | --- | --- |
| `presetDollars` | 10, 20, 50, 100 | the quick-pick buttons |
| `maximumDollars` | 10,000 | the largest amount the keypad accepts |
| `cardPromptTimeout` | 180 | seconds the card prompt waits before the kiosk cancels |
| `saveDonorsToSquare` | true | also add phone numbers to the Square Customer Directory |

## Where phone numbers go

1. **The day's log on the iPad** (always). See below.
2. **The Square Customer Directory** (when `saveDonorsToSquare` is on). The
   donor is found by phone number, or created if new. Each donation is added
   as a line on their profile's note, for example
   `2026-10-02 kiosk donation $50 (payment abc123)`. Square doesn't allow
   attaching a customer to a payment after it is taken, and the phone number
   is asked for after payment, so the note and the log are what connect the
   two.

## The day's log

The kiosk writes one CSV row per donation attempt, one file per day, named
`kiosk-log-YYYY-MM-DD.csv`:

```
timestamp,amount,status,phone,payment_id,saved_to_square,note
2026-10-02T13:05:12-05:00,50,ok,(555) 123-4567,R2B3…,yes,
2026-10-02T13:20:40-05:00,20,ok,,Kx9…,,
2026-10-02T14:02:03-05:00,100,declined,,,,Card declined.
```

| status | meaning |
| --- | --- |
| `ok` | paid. `phone` is empty if the donor skipped it. |
| `declined` | not paid: card declined or Square error |
| `UNCONFIRMED` | the payment failed on the iPad and Square couldn't be reached to check it. Look in the Square Dashboard; the note includes the payment's reference ID. |

If a donor cancels, or the card prompt times out, no money moves and no row
is written.

**Downloading it.** The iPad serves its logs on the masjid's network:

```sh
curl -u admin:admin -OJ http://<ipad-ip>:8080/log            # today
curl -u admin:admin -OJ http://<ipad-ip>:8080/log/2026-10-02 # one day
```

You can also open `http://<ipad-ip>:8080/` in a browser to see every day's
log. The staff page shows the iPad's address. **The log contains donors'
phone numbers**, so change `logServerUser` / `logServerPassword`, and keep
the kiosk off any Wi-Fi network the public can join.

## Kiosk hardening

- Lock the iPad to this app with **Guided Access** (Settings → Accessibility).
- Set **Auto-Lock** to **Never**, and turn off notifications.
- Give the iPad a DHCP reservation so its log address stays the same.
- The access token is built into the app. Anyone who has the device image
  could extract it, so treat the iPad as a key to the Square account. Rotate
  the token if the iPad is lost.

## Project layout

```
MasjidKiosk/
├── KioskConfig.swift            ← credentials, amounts, timeouts
├── Models/Donation.swift        Donation + PhoneNumber
├── Payments/
│   ├── SquareAPI.swift          minimal Square REST client
│   ├── StandPaymentService      Mobile Payments SDK payment on the Stand
│   ├── SquareReader.swift       SDK sign-in, permissions, reader status
│   └── DemoPaymentService.swift
├── Donors/DonorDirectory.swift  Square Customer Directory upsert
├── Logging/                     day's CSV + HTTP download server
├── en.lproj/Localizable.strings all donor-facing wording
└── Views/                       Home → Amount → Paying → Phone → Thanks, + Staff
```

Debug builds can jump straight to a screen for screenshots with
`-kioskStartStep amount|paying|phone|thanks|failure|unconfirmed`.

## Build from the command line

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MasjidKiosk.xcodeproj -scheme MasjidKiosk \
  -destination 'generic/platform=iOS Simulator' build
```

Leave code signing on: Square's setup build phase re-signs its frameworks and
fails without a signing identity.
