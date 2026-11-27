# Rastro development log

A record of every change set: what was wrong, the code before and after, why the change
fixes it, and how it was checked. Newest entry first.

This is the **engineering** log, kept for you and future contributors. When the app ships,
also keep a short user-facing `CHANGELOG.md` ("1.1: Fixed duplicate visits") for release notes.

**Template for new entries**

```
## YYYY-MM-DD: <short title>
Branch: `<branch>` · PR: #<n>

### <change>
- Problem: what went wrong, with a concrete example
- Before / After: the relevant code
- Why it works: the reasoning, in a few sentences
- Verified by: test names, builds, manual checks
```

---

## 2026-11-26: Fix visit-recording bugs, add unit tests, fix preview data
Branch: `fix/visit-recording-bugs`

This came from a `/code-review` of the first branch, which found bugs that were already in
the app (none of them were caused by the comment changes). Three were new, and two were
already in the roadmap doc.

### 1. Visit merge rules moved into `VisitRecorder` (fixes review bugs 1, 2 and 4)

**Problem.** `LocationTracker.save(visit:)` decided "is this the same stay?" by looking only
for an *open* visit within 200 m. That fails three ways:

- **Bug 1, lost visit.** iOS never sends yesterday's "left home" event. Tonight you arrive
  home, the arrival matches yesterday's still-open home visit, and the code "closes" it with a
  departure of nil, which does nothing. Today's visit is never saved, and yesterday's grows
  past 24 h.
- **Bug 2, duplicate visit.** Events arrive as: arrive A → arrive B (A is closed as stale) →
  A's late departure. That departure finds no *open* visit near A, so a second A is inserted
  and A's time is counted twice.
- **Bug 4, negative duration.** When iOS doesn't know the arrival time (`distantPast`), the
  arrival was set to *now*, which is after the real departure, so duration came out negative.

**Before** (`LocationTracker.swift`):

```swift
private func save(visit clVisit: CLVisit) {
    guard let context = container?.mainContext else { return }

    let arrival = clVisit.arrivalDate == .distantPast ? Date.now : clVisit.arrivalDate   // ← bug 4
    let departure: Date? = clVisit.departureDate == .distantFuture ? nil : clVisit.departureDate
    let coord = clVisit.coordinate

    let open = FetchDescriptor<Visit>(predicate: #Predicate { $0.departure == nil })
    if let existing = (try? context.fetch(open))?.first(where: {                         // ← bugs 1 and 2:
        CLLocation(latitude: $0.latitude, longitude: $0.longitude)                       //   only OPEN visits,
            .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) < 200
    }) {                                                                                 //   matched by distance only
        existing.departure = departure
        try? context.save()
        return
    }

    if let dangling = try? context.fetch(open) {
        for v in dangling { v.departure = v.departure ?? arrival }
    }

    let visit = Visit(arrival: arrival, departure: departure,
                      latitude: coord.latitude, longitude: coord.longitude)
    context.insert(visit)
    try? context.save()
    geocode(visit)
}
```

**After.** `save(visit:)` is now three lines. The rules moved to the new
`Rastro/Location/VisitRecorder.swift`:

```swift
private func save(visit clVisit: CLVisit) {
    guard let context = container?.mainContext else { return }
    if let newVisit = VisitRecorder.record(VisitEvent(clVisit), in: context) {
        enqueueGeocoding([newVisit.persistentModelID])
    }
}
```

```swift
static func record(_ event: VisitEvent, in context: ModelContext) -> Visit? {
    // Rule 0: ignore nonsense (no dates, or departure before arrival)
    if let arrival = event.arrival, let departure = event.departure, departure < arrival { return nil }
    guard let start = event.arrival ?? event.departure else { return nil }
    let here = CLLocation(latitude: event.latitude, longitude: event.longitude)

    // Rule 1: same stay already saved? (arrival ±5 min, within 200 m, open OR closed)
    if let arrival = event.arrival,
       let existing = visit(arrivingAround: arrival, near: here, in: context) {
        if let departure = event.departure { existing.departure = departure }
        try? context.save()
        return nil
    }

    // Rule 2: departure with unknown arrival → close the open visit here
    if event.arrival == nil, let departure = event.departure,
       let existing = openVisits(in: context)
           .filter({ $0.arrival <= departure && isNear($0, here) })
           .max(by: { $0.arrival < $1.arrival }) {
        existing.departure = departure
        try? context.save()
        return nil
    }

    // Rule 3: a new stay. Close older open visits, then insert.
    for stale in openVisits(in: context) where stale.arrival < start {
        stale.departure = leftTime(of: stale, before: start, in: context)
    }
    let visit = Visit(arrival: start, departure: event.departure,
                      latitude: event.latitude, longitude: event.longitude)
    context.insert(visit)
    try? context.save()
    return visit
}
```

**Why it works.**

- iOS reports both halves of a stay with the **same arrival date**, so matching on arrival
  time (plus distance) identifies a stay exactly. A new arrival at home has a *different*
  arrival time from yesterday's, so it no longer merges (bug 1). A late departure still finds
  its visit even after it was closed as stale, because Rule 1 also searches closed visits
  (bug 2).
- An unknown arrival is now `nil` instead of "now". The code uses the departure time, which
  gives a zero-length visit and never a negative one (bug 4). As a safety net for old bad
  rows, `Visit.duration` is now `max(0, …)`.
- **Bonus: stale visits get a realistic end time.** `leftTime(of:before:in:)` uses the first
  breadcrumb more than 200 m away as the departure, instead of "whenever you next arrived
  somewhere". Without it, a missed "left home" event made home last until the next evening.
- `VisitEvent` is a plain struct, because tests can't easily create a real `CLVisit`.
  Splitting the logic out is what makes the rules testable.

**Verified by:** `RastroTests/VisitRecorderTests.swift`, one test per bug scenario:
`newArrivalAtSamePlace`, `staleVisitUsesBreadcrumbs`, `lateDeparture`, `unknownArrivalNoMatch`,
`unknownArrivalClosesOpenVisit`, `departureBeforeArrival`, `durationClamp`, plus the normal
arrival/departure, a repeated event, and the return value.

### 2. Geocoding: one queue, survives deletion (fixes review bugs 3 and 5, and a build warning)

**Problem.**

- **Bug 3, crash risk.** The geocoding completion held the `Visit` object and wrote to it
  seconds later. If the user deleted the visit (or tapped "Delete all") in the meantime, it
  wrote to a deleted SwiftData model, which can crash or bring the row back.
- **Bug 5, overlapping requests.** Every foreground started a new 20-item loop, and every new
  visit fired its own request. These overlapped on the single `CLGeocoder`, so requests failed
  and visits stayed unnamed. Visits with no city (sea, countryside) were retried on every
  launch, forever.
- **Build warning:** "capture of 'visit' with non-Sendable type 'Visit' in a '@Sendable'
  closure", from the same code.

**Before:**

```swift
private func geocode(_ visit: Visit) {
    let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
    geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
        guard let pm = placemarks?.first else { return }
        Task { @MainActor in
            visit.name = pm.areasOfInterest?.first ?? pm.name   // ← may be a deleted model (bug 3)
            visit.locality = pm.locality
            visit.adminArea = pm.administrativeArea
            visit.country = pm.country
            try? self?.container?.mainContext.save()
        }
    }
}

func geocodeMissing() {
    guard let context = container?.mainContext else { return }
    let missing = FetchDescriptor<Visit>(predicate: #Predicate { $0.locality == nil })   // ← no-city places retried forever
    let visits = (try? context.fetch(missing)) ?? []
    Task { @MainActor in                                  // ← a new loop on every call (bug 5)
        for v in visits.prefix(20) {
            geocode(v)
            try? await Task.sleep(for: .seconds(1.5))
        }
    }
}
```

**After:**

```swift
private var geocodeQueue: [PersistentIdentifier] = []
private var geocodeWorker: Task<Void, Never>?

private func enqueueGeocoding(_ ids: [PersistentIdentifier]) {
    for id in ids where !geocodeQueue.contains(id) { geocodeQueue.append(id) }
    guard geocodeWorker == nil else { return }        // only ONE worker ever runs
    geocodeWorker = Task {
        while !geocodeQueue.isEmpty {
            let id = geocodeQueue.removeFirst()
            await geocode(id)                          // waits for each request to finish
            try? await Task.sleep(for: .seconds(1.5))
        }
        geocodeWorker = nil
    }
}

private func geocode(_ id: PersistentIdentifier) async {
    guard let context = container?.mainContext,
          let visit = VisitRecorder.liveVisit(id, in: context) else { return }
    let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
    guard let pm = try? await geocoder.reverseGeocodeLocation(location).first else { return }
    guard let stillThere = VisitRecorder.liveVisit(id, in: context) else { return }   // deleted while waiting?
    stillThere.name = pm.areasOfInterest?.first ?? pm.name
    // … locality, adminArea, country …
    try? context.save()
}

func geocodeMissing() {
    guard let context = container?.mainContext else { return }
    var missing = FetchDescriptor<Visit>(predicate: #Predicate { $0.name == nil })
    missing.fetchLimit = 20
    enqueueGeocoding(((try? context.fetch(missing)) ?? []).map(\.persistentModelID))
}
```

**Why it works.**

- The queue stores **database IDs, not objects**. After the network wait, `liveVisit` fetches
  the visit again, and the fetch returns nothing if the visit was deleted. So a deleted
  visit is never written to (bug 3). It also removes the non-Sendable capture, which was the
  cause of the build warning.
- **One worker, one request at a time.** The `async` version of `reverseGeocodeLocation` lets
  the worker wait for each answer before the 1.5 s pause. Calling `geocodeMissing()` again
  only adds IDs that aren't already queued, and never starts a second loop (bug 5).
- "Missing" now means **no name** instead of no city. Any successful lookup sets a name (for
  the sea, its name), so those places stop being retried. Visits that truly failed (offline)
  still have no name and are retried, which is what we want.

**Verified by:** test `liveVisitAfterDelete`, and a clean Release build with zero Swift
warnings. The network part (real geocoding) needs a manual check on a phone: record a visit,
then delete it immediately. The app should not crash and the visit should not come back.

### 3. Preview data fixes (review nits)

- **Fake lines across the country.** Breadcrumbs were drawn between *every* pair of visits,
  including trips months apart, which inflated km in the Year preview.

  ```swift
  // Before
  guard gap > 0 else { continue }
  // After: only within one journey
  guard gap > 0, gap < 12 * hour else { continue }
  ```
- **The Month preview depended on the date.** The Lisbon trip sat 21 days back, so it fell
  in the previous month for most of the month. It's now about 9 days back (just before the
  Madrid week), and the header comment says honestly that the Month tab shows it from about
  the 12th onward.

**Verified by:** Debug build; open the "Share card · month" / "Recap · sample data" previews.

### 4. Test target

- `project.yml`: new `RastroTests` unit-test target (Swift Testing), and the `Rastro` scheme
  now runs it, so ⌘U works. Run `xcodegen generate` after pulling.
- `RastroTests/RecapStatsTests.swift`: first recap tests (unique places, city and country
  lists, ranking by time, the jitter filter, distance sum, day filtering).

**Verified by:** `xcodebuild test`, 15 tests in 2 suites, all passing.

---

## 2026-11-26: Document the codebase and add SwiftUI previews
Branch: `docs/code-comments-and-previews` · Commit `38e52f5`

- **Comments in all 11 Swift files.** Each file got a header with its purpose and links to
  related files, `MARK:` sections for Xcode's jump bar (`⌃6`), doc comments (`⌥`-click shows
  them), and `NOTE:` tags for known issues. No code changed: it was checked by stripping
  comments and diffing against the previous commit, plus a build.
- **`ARCHITECTURE.md`**: reading order, data flow diagram, lifecycle walkthroughs, App Store
  checklist, known limitations.
- **Previews.** `Rastro/Preview/PreviewData.swift` adds Debug-only, in-memory sample data, and
  every screen got `#Preview` blocks, so the canvas (`⌥⌘↩`) shows real-looking screens.
  `#if DEBUG` keeps the sample data out of App Store builds; checked by a Release build with
  no `PreviewData` symbols in the binary.
