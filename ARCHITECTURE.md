# Rastro — how the app works

A guide for reviewing the code. Every Swift file starts with a header explaining its job;
this page shows how the pieces fit together and the order to read them in.

## 1. Reading order (≈1,000 lines, about an hour)

| # | File | What you'll learn |
|---|------|-------------------|
| 1 | `Rastro/RastroApp.swift` | Launch, database creation, why the tracker starts in `init()` |
| 2 | `Rastro/Models/Models.swift` | The only two things stored: `Visit` and `LocationPoint` |
| 3 | `Rastro/Location/LocationTracker.swift` | **The core.** Permissions, iOS location events → database rows, geocoding |
| 4 | `Rastro/Views/RootView.swift` | Onboarding vs. tabs; what happens when the app opens |
| 5 | `Rastro/Views/OnboardingView.swift` | Permission screens and the "Allow Always" banner |
| 6 | `Rastro/Recap/RecapStats.swift` | All the recap math (pure functions, easy to test) |
| 7 | `Rastro/Recap/RecapView.swift` | The main screen, built from `RecapStats` |
| 8 | `Rastro/Recap/ShareRecap.swift` | The shareable "Wrapped" image |
| 9 | `Rastro/Views/HistoryView.swift`, `AllPlacesMapView.swift`, `SettingsView.swift` | The other tabs |
| 10 | `project.yml`, `Rastro/Info.plist`, `Rastro/PrivacyInfo.xcprivacy` | Build settings, permission text, Apple privacy manifest |

Search for `MARK:` in Xcode (the jump bar above the editor) to move between sections of a file,
and for `NOTE:` to find known limitations and ideas for improvement.

### Previews (see each screen without running the app)

Open any file under `Recap/` or `Views/` and press `⌥⌘↩` to show the canvas. Every screen has
`#Preview` blocks at the bottom; pick one from the bar at the top of the canvas. They use fake
data from `Rastro/Preview/PreviewData.swift` (a week in Madrid, a Lisbon weekend, a Valencia
trip), stored in memory and compiled only in Debug builds, so it never ships. Click something in
the canvas to jump to the code that draws it, or press ▶ to tap around.

After adding or removing a `.swift` file, run `xcodegen generate` so the Xcode project picks it
up (the `.xcodeproj` is generated from `project.yml` and isn't in git).

## 2. The big picture

```
                ┌─────────────────────────── iPhone ───────────────────────────┐
 iOS location   │                                                              │
 services ──────┼─► LocationTracker ──save──► SwiftData database ◄──@Query── Views
 (visits,       │     (singleton)              (Visit, LocationPoint)     (Recap, History,
  ~500 m moves) │        │                                                 Map, Settings)
                │        └─geocode─► Apple geocoding server (the only network use)
                └──────────────────────────────────────────────────────────────┘
```

- **One writer, many readers.** Only `LocationTracker` creates data. Views read with `@Query`
  and redraw by themselves when data changes. The only other writes are user deletes
  (History swipe, Settings "Delete all").
- **No view models.** SwiftUI views read the database directly. The recap logic lives in one
  plain struct (`RecapStats`), so it can be tested without any UI.
- **No server, no accounts.** Everything is stored in the app's private storage on the phone.

## 3. Lifecycle walkthroughs

### First launch
1. `RastroApp.init()` creates the database and calls `LocationTracker.shared.configure(...)`.
2. There's no permission yet, so `RootView` shows `OnboardingView`.
3. Tapping **Start tracking** calls `requestPermission()`, and iOS shows "Allow While Using".
4. iOS calls `locationManagerDidChangeAuthorization`. That updates `authorizationStatus`, which
   makes `RootView` switch to the tabs, and `startIfAuthorized()` turns monitoring on.
5. The Recap tab shows the **Allow Always** banner. Tapping it asks iOS to upgrade the permission.

### You arrive at a café (app closed)
1. iOS detects the visit and relaunches Rastro in the background. `RastroApp.init()` runs and
   no window is shown.
2. `locationManager(_:didVisit:)` → `save(visit:)` inserts an **open** `Visit` (no departure).
3. `geocode(_:)` fills in "Café X, Madrid, Spain".
4. When you leave, iOS sends the same visit again with a departure date. `save(visit:)` finds
   the open visit within 200 m and closes it.

### You open the Recap tab
1. `@Query` loads every visit and point.
2. `RecapStats.make(period:anchor:...)` filters them to the selected period and calculates
   distance, top places, cities and countries.
3. `RecapView` draws the result. `ShareRecapButton` renders `RecapCard` into an image to share.

## 4. Key iOS concepts used

| Concept | Where | One-line explanation |
|---|---|---|
| `CLLocationManager.startMonitoringVisits()` | LocationTracker | iOS reports arrive/leave events for places, using very little battery |
| `startMonitoringSignificantLocationChanges()` | LocationTracker | About one update per ~500 m of movement, from cell/Wi-Fi |
| "Always" permission + `UIBackgroundModes: location` | LocationTracker, project.yml | Needed to receive events while the app is closed |
| `@Model`, `ModelContainer`, `@Query` | Models, RastroApp, views | SwiftData: a database whose changes automatically refresh the UI |
| `@MainActor` / `nonisolated` | LocationTracker | Do all work on the main thread; the iOS callbacks hop over to it |
| `ObservableObject` + `@Published` + `@EnvironmentObject` | LocationTracker → views | Shared state the UI watches |
| `ImageRenderer` + `ShareLink` | ShareRecap | Turn a SwiftUI view into an image and share it |

## 5. Before the App Store — checklist

- [ ] **Privacy policy URL**: `SettingsView.privacyURL` is still a placeholder. Host
      `PRIVACY_POLICY.md` (for example on GitHub Pages) and put the real link there and in App Store Connect.
- [ ] **Bundle ID / Team**: `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`.
- [ ] **Version numbers**: increase `CURRENT_PROJECT_VERSION` for every upload and
      `MARKETING_VERSION` for each release.
- [ ] **Location usage strings** (`project.yml` → `info.properties`; Info.plist is generated
      from it) must honestly explain why "Always" is needed. App Review checks this closely.
- [ ] **App Privacy questionnaire**: location data is collected but never leaves the device
      except for the geocoding lookup, and it isn't linked to the user or used for tracking.
- [ ] **Data model changes after launch**: set up a SwiftData `VersionedSchema` migration
      before changing `Visit` or `LocationPoint` in an update (see the note in `RastroApp.swift`).

## 6. Known limitations / improvement ideas

These are also marked with `NOTE:` comments in the code.

- **Performance**: `RecapView` filters *all* data in memory on every redraw, and the share image
  is re-rendered on every redraw. Use date-ranged queries, and render the image when the
  share button is tapped.
- **Geocoding**: places with no city are retried every time the app opens, and two retry
  loops can run at the same time. The build shows a concurrency warning in `geocode(_:)`
  (a non-`Sendable` `Visit` captured in a closure). Consider MapKit's newer
  reverse-geocoding API.
- **Place grouping**: `placeKey` changes once a visit is geocoded, and nearby visits can fall
  into different ~110 m grid cells. Distance-based clustering would group places better.
- **"Allow Always" banner** opens the permission prompt and the Settings app on the same tap.
- **Settings** loads every row just to count them (`fetchCount` would be cheaper).
- **Localization**: all user-facing text is hard-coded English. A String Catalog would allow
  Spanish and other languages.
- **Tests**: there are none yet. `RecapStats.make` is the best place to start (pure input → output).
- `daysTracked` is calculated but not shown anywhere yet.
