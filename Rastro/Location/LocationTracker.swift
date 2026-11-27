//
//  LocationTracker.swift
//  Rastro
//
//  LOCATION ENGINE — the heart of the app. Everything Rastro records comes through here.
//
//  What it does:
//   • Asks the user for location permission (When In Use → then Always).
//   • Turns on two low-power iOS location services and listens to them.
//   • Converts each iOS event into a `Visit` or `LocationPoint` and saves it to SwiftData.
//   • Reverse-geocodes visits (coordinates → "Café X, Madrid, Spain").
//   • Publishes permission + on/off state so the UI can react (`ObservableObject`).
//
//  Event flow:
//
//     iOS (CLLocationManager)
//        │  delegate callback, on some thread
//        ▼
//     `nonisolated func locationManager(...)`   ← bottom of this file
//        │  hops to the main thread with `Task { @MainActor in ... }`
//        ▼
//     `save(visit:)` → VisitRecorder (merge rules)  ┐
//     `save(points:)`                              ┴→ SwiftData mainContext → views refresh via @Query
//        │
//        ▼
//     geocoding queue → `geocode(_:)` (async, Apple's servers) → fills name/city/country → save again
//
//  Why a singleton (`shared`)? There must be exactly one CLLocationManager listening, and
//  it has to exist even when no UI is on screen (background relaunch). RastroApp creates
//  it at launch and passes it into the views.
//

import Foundation
import CoreLocation
import SwiftData

/// Owns the CLLocationManager and writes everything it hears into SwiftData.
///
/// Battery strategy: we never run continuous GPS. We use two low-power iOS services:
///  • Visit monitoring  → "you arrived at / left a place"
///  • Significant location changes → a point roughly every ~500 m of movement
/// Both keep working when the app is closed: iOS relaunches it in the background.
///
/// `@MainActor`: all properties and methods run on the main thread. This keeps SwiftData's
/// `mainContext` and the `@Published` properties (which drive the UI) safe to touch.
/// `NSObject` is required because `CLLocationManagerDelegate` is an Objective-C protocol.
@MainActor
final class LocationTracker: NSObject, ObservableObject {
    static let shared = LocationTracker()

    // MARK: - Published state (the UI observes these)

    /// Current iOS permission level (notDetermined / denied / whenInUse / always…).
    /// `private(set)`: only this class changes it, from the delegate callback.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    /// The "Record my places" toggle in Settings. Persisted in UserDefaults so it
    /// survives relaunches; flipping it immediately starts or stops monitoring.
    @Published var isTrackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTrackingEnabled, forKey: Self.trackingKey)
            isTrackingEnabled ? startIfAuthorized() : stop()
        }
    }

    // MARK: - Private state

    private static let trackingKey = "trackingEnabled"   // UserDefaults key
    private let manager = CLLocationManager()            // the iOS location service
    private let geocoder = CLGeocoder()                  // coordinates → address (network)
    private var container: ModelContainer?               // set by configure(); nil = can't save yet

    // MARK: - Setup

    /// Private so nobody can create a second tracker — use `LocationTracker.shared`.
    private override init() {
        authorizationStatus = manager.authorizationStatus
        // Default to ON the first time (no saved value yet).
        isTrackingEnabled = UserDefaults.standard.object(forKey: Self.trackingKey) as? Bool ?? true
        super.init()
        manager.delegate = self
        // 100 m is plenty for "which place were you at" and much cheaper than GPS-level accuracy.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Don't let iOS decide to stop updates when you seem stationary — we want every event.
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Called once from `RastroApp.init()`. Gives the tracker the database and, if the
    /// user already granted permission on a previous launch, starts monitoring right away.
    func configure(container: ModelContainer) {
        self.container = container
        startIfAuthorized()
    }

    // MARK: - Permissions

    /// iOS requires asking for "When In Use" first, then upgrading to "Always".
    ///
    /// Called from the onboarding button and the "Allow Always" banner.
    /// Step 1 (.notDetermined)       → system prompt "Allow While Using / Once / Don't Allow".
    /// Step 2 (.authorizedWhenInUse) → system prompt "Change to Always Allow".
    /// iOS only shows each prompt once; after that the user must go to the Settings app.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// True only with "Always" — required for logging while the app is closed.
    var hasAlways: Bool { authorizationStatus == .authorizedAlways }

    /// True with either "Always" or "While Using". RootView uses this to decide between
    /// onboarding and the main tabs.
    var hasAnyPermission: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    // MARK: - Start / stop monitoring

    /// Turns on both location services, but only if the toggle is on AND we have permission.
    /// Safe to call repeatedly (iOS ignores duplicate "start" calls).
    private func startIfAuthorized() {
        guard isTrackingEnabled, hasAnyPermission else { return }
        if hasAlways {
            // Required (together with UIBackgroundModes=location in Info.plist) to receive
            // events while the app is in the background.
            manager.allowsBackgroundLocationUpdates = true
            // Hide the blue status-bar pill; these low-power services don't need it.
            manager.showsBackgroundLocationIndicator = false
        }
        // Service 1: arrivals / departures → Visit rows.
        manager.startMonitoringVisits()
        // Service 2: ~500 m movement updates → LocationPoint rows. (Unavailable on some
        // devices / the simulator, hence the check.)
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    /// Turns both services off (Settings toggle switched off).
    private func stop() {
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - Saving events to the database

    /// Converts an iOS `CLVisit` into a `Visit` row (or updates an existing one).
    /// All the merge / dedupe / stale-visit rules live in `VisitRecorder` (tested in
    /// RastroTests); here we only translate the event and queue a name lookup.
    private func save(visit clVisit: CLVisit) {
        guard let context = container?.mainContext else { return }
        if let newVisit = VisitRecorder.record(VisitEvent(clVisit), in: context) {
            enqueueGeocoding([newVisit.persistentModelID])
        }
    }

    /// Saves movement breadcrumbs. iOS may batch several locations into one callback.
    private func save(points: [CLLocation]) {
        guard let context = container?.mainContext else { return }
        // Skip invalid fixes (negative accuracy = invalid) and very imprecise ones (> 1 km),
        // which would draw zig-zags on the map and inflate km traveled.
        for loc in points where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 1_000 {
            context.insert(LocationPoint(timestamp: loc.timestamp,
                                         latitude: loc.coordinate.latitude,
                                         longitude: loc.coordinate.longitude,
                                         horizontalAccuracy: loc.horizontalAccuracy))
        }
        try? context.save()
    }

    // MARK: - Reverse geocoding (coordinates → place names)

    // How it works: visits to name go into ONE queue, and ONE worker task drains it,
    // one request at a time with a pause between them. CLGeocoder handles one request
    // at a time and Apple rate-limits it, so overlapping requests would just fail.
    // The queue holds database IDs, not Visit objects, so a visit deleted while it
    // waits is simply skipped.

    private var geocodeQueue: [PersistentIdentifier] = []   // waiting to be named
    private var geocodeWorker: Task<Void, Never>?            // nil = no worker running

    /// Adds visits to the naming queue (skipping ones already queued) and starts the
    /// worker if it isn't running. Safe to call any number of times.
    private func enqueueGeocoding(_ ids: [PersistentIdentifier]) {
        for id in ids where !geocodeQueue.contains(id) {
            geocodeQueue.append(id)
        }
        guard geocodeWorker == nil else { return }   // the running worker will get to them
        geocodeWorker = Task {
            while !geocodeQueue.isEmpty {
                let id = geocodeQueue.removeFirst()
                await geocode(id)
                try? await Task.sleep(for: .seconds(1.5))   // stay under Apple's rate limit
            }
            geocodeWorker = nil
        }
    }

    /// Turns coordinates into "Café X, Walnut Creek, United States" for one visit.
    ///
    /// Uses Apple's geocoding servers (needs internet). The lookup takes time, and the user
    /// may delete the visit meanwhile, so we re-fetch it by ID AFTER the lookup and only
    /// write if it still exists.
    private func geocode(_ id: PersistentIdentifier) async {
        guard let context = container?.mainContext,
              let visit = VisitRecorder.liveVisit(id, in: context) else { return }
        let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)

        // Offline / rate-limited / no result → leave it unnamed; geocodeMissing() retries later.
        guard let pm = try? await geocoder.reverseGeocodeLocation(location).first else { return }

        guard let stillThere = VisitRecorder.liveVisit(id, in: context) else { return }   // deleted while waiting
        // Prefer a point of interest ("Retiro Park") over a street address.
        stillThere.name = pm.areasOfInterest?.first ?? pm.name
        stillThere.locality = pm.locality
        stillThere.adminArea = pm.administrativeArea
        stillThere.country = pm.country
        try? context.save()
    }

    /// Fills in names for visits recorded while offline / rate-limited.
    ///
    /// Called by RootView every time the app comes to the foreground. A visit counts as
    /// "missing" while it has no `name`. (It used to check the city, so places that have
    /// no city, like the sea, were looked up again on every launch.) At most 20 per call;
    /// the queue ignores visits that are already waiting, so calling this often is harmless.
    func geocodeMissing() {
        guard let context = container?.mainContext else { return }
        var missing = FetchDescriptor<Visit>(predicate: #Predicate { $0.name == nil })
        missing.fetchLimit = 20
        let visits = (try? context.fetch(missing)) ?? []
        enqueueGeocoding(visits.map(\.persistentModelID))
    }
}

// MARK: - CLLocationManagerDelegate (iOS → Rastro callbacks)
//
// iOS calls these methods. They're `nonisolated` because iOS doesn't promise to call them
// on the main thread; each one immediately forwards the work to the main actor where the
// rest of the class lives.

extension LocationTracker: CLLocationManagerDelegate {
    /// Permission changed (user answered a prompt, or changed it in the Settings app).
    /// Also fires once right after the manager is created.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status   // UI updates (onboarding ↔ tabs, banner)
            self.startIfAuthorized()            // begin tracking as soon as permission arrives
        }
    }

    /// Visit monitoring: you arrived at, or left, a place.
    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in self.save(visit: visit) }
    }

    /// Significant location change: you moved roughly 500 m.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.save(points: locations) }
    }

    /// Errors (e.g. location temporarily unavailable). Only logged — nothing to recover.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
