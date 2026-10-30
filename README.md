# Rastro — your private "where I've been" recap app (iOS)

Rastro logs the places you visit in the background (low battery, no constant GPS) and turns them into **monthly, yearly and all-time recaps**: places, cities, countries, km traveled, top spots, a map of your path, and a shareable "Wrapped"-style card.

- SwiftUI + SwiftData + CoreLocation + MapKit, iOS 17+
- No server, no accounts: all data stays on the phone
- Tabs: **Recap · History · Map · Settings** (pause tracking, delete all data)

```
Rastro/
├── project.yml                 # XcodeGen spec → generates Rastro.xcodeproj
└── Rastro/
    ├── RastroApp.swift         # app entry, SwiftData container, starts tracker
    ├── Models/Models.swift     # Visit + LocationPoint
    ├── Location/LocationTracker.swift   # permissions, visits, significant changes, geocoding
    ├── Recap/                  # stats math, recap screen, share card
    ├── Views/                  # onboarding, history, map, settings
    ├── Assets.xcassets         # app icon (1024px, replace with your own anytime)
    ├── Info.plist              # location usage strings + background mode
    └── PrivacyInfo.xcprivacy   # Apple privacy manifest (required)
```

---

## Part 1 — Run it on your iPhone

You need a **Mac with Xcode 26 or later** (Apple rejects uploads built with older Xcode since April 28, 2026).

1. **Install tools**
   ```bash
   xcode-select --install          # if you've never used Xcode CLI tools
   brew install xcodegen
   ```
2. **Generate the Xcode project**
   ```bash
   cd Rastro
   xcodegen generate
   open Rastro.xcodeproj
   ```
   *No Homebrew?* Create a new Xcode project instead (iOS → App, name `Rastro`, SwiftUI, storage **SwiftData**), delete its generated Swift files, drag the `Rastro/` folder contents in, set the target's Info.plist to `Rastro/Info.plist`, and under **Signing & Capabilities → + Background Modes** tick **Location updates**.
3. **Change the bundle ID**: in `project.yml` (or Xcode → target → General) replace `com.yourname.rastro` with something unique like `com.diegog.rastro`.
4. **Signing**: Xcode → target → *Signing & Capabilities* → tick *Automatically manage signing* → pick your Team (sign in with your Apple ID under Xcode → Settings → Accounts).
5. **Run on device**: plug in your iPhone, enable *Developer Mode* (iPhone Settings → Privacy & Security → Developer Mode), select it in Xcode, press ▶︎.
6. In the app: **Start tracking** → *Allow While Using* → tap again / banner → *Change to Always Allow*.

### Testing tips
- Visits only appear after you **stay somewhere ~5+ minutes and leave**. Give it a day.
- Simulator: *Features → Location → Freeway Drive* produces points (visits rarely fire in the simulator; a real phone is best).
- Background test: force-quit the app, go somewhere, come back — iOS relaunches it in the background to log the visit.

---

## Part 2 — Publish to the App Store (step by step)

### 1. Join the Apple Developer Program
- developer.apple.com/programs → Enroll ($99/year). Individual is fine; takes ~1–2 days to approve.
- As an individual, your **legal name shows as the seller** on the store. Want "Rastro LLC" instead? Enroll as an organization (needs a D-U-N-S number).

### 2. Host a privacy policy (required)
- Use `PRIVACY_POLICY.md` in this repo. Easiest: create a public GitHub repo → add it → Settings → Pages → enable. You'll get a URL like `https://yourname.github.io/rastro/privacy`.
- Put that URL in `SettingsView.swift` (`privacyURL`) and in App Store Connect.

### 3. Register the app ID
- developer.apple.com → Certificates, IDs & Profiles → Identifiers → **+** → App IDs → App → bundle ID exactly as in Xcode (e.g. `com.diegog.rastro`). (Xcode's automatic signing usually does this for you.)

### 4. Create the app in App Store Connect
- appstoreconnect.apple.com → **Apps → +  → New App**
  - Platform: iOS · Name: *Rastro* (must be unique on the store — have backups like "Rastro: Places Recap") · Language · Bundle ID · SKU (anything, e.g. `rastro001`)

### 5. Archive & upload the build
1. Xcode → top bar device → **Any iOS Device (arm64)**
2. Bump version/build if re-uploading (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate` again).
3. **Product → Archive** → Organizer opens → **Distribute App → App Store Connect → Upload**.
4. Wait ~10–30 min for "processing" to finish in App Store Connect (you'll get an email).

### 6. TestFlight (strongly recommended)
- App Store Connect → your app → TestFlight → add yourself as an internal tester → install via the TestFlight app and live with it for a week. Catch bugs before Apple's reviewers do.

### 7. Fill out the store listing
| Field | What to put |
|---|---|
| Subtitle | "Your private travel recap" |
| Description | What it does + "All data stays on your device. No account." |
| Keywords | places, travel, diary, journal, recap, location history, map, visits |
| Category | Travel (secondary: Lifestyle) |
| Screenshots | **6.9" iPhone** required (1320×2868). Take them on an iPhone 16/17 Pro Max simulator with sample data (⌘S in Simulator). |
| Support URL | Your GitHub Pages site or repo |
| Privacy Policy URL | From step 2 |
| Age rating | Answer the questionnaire (should come out 4+) |
| Price | Free (or set a price in *Pricing and Availability*) |

### 8. App Privacy ("nutrition label")
App Store Connect → *App Privacy*. Because **nothing leaves the device**, the answer is **"No, we do not collect data from this app."** ("Collect" means sent off the device to you or a third party.)
⚠️ If you later add analytics, crash reporting, or cloud sync, you must update this to declare **Precise Location**.

### 9. App Review notes (important for background location)
Apple scrutinizes "Always" location. In *App Review Information → Notes* write something like:
> Rastro is a personal location diary. It uses visit monitoring and significant-location-change (low power, no continuous GPS) in the background to build the user's own monthly/yearly recaps. Background location is the app's core feature; all data is stored only on the device and can be deleted in Settings. To test: grant "Always", move around for a few minutes or use a simulated route; recaps appear in the Recap tab.

Optionally attach a short screen recording showing the permission flow and a recap with data.

### 10. Submit
- Select your build under the version → **Add for Review → Submit**.
- Review typically takes 1–3 days. If rejected, read the message in *Resolution Center*, fix, bump the build number, re-upload, resubmit.
- Choose *Manually release* if you want to pick the launch day.

### Common rejection reasons for apps like this
- Vague location purpose strings → ours explain the benefit clearly (Info.plist).
- Missing/broken privacy policy link.
- Reviewer saw an empty app → mention testing steps in notes (step 9).
- Placeholder content (e.g. the `yourname` privacy URL) left in the build.

---

## Ideas for v2
- iCloud sync via SwiftData + CloudKit (then update App Privacy)
- Home-screen widget: "This month: 23 places, 412 km"
- Year-end animated recap (like Spotify Wrapped), photos from that day (PhotoKit)
- Export to GPX/CSV, import Google Maps Timeline
- Swap `CLGeocoder` for MapKit's newer reverse-geocoding API (CLGeocoder is deprecated as of iOS 26 but still works)
