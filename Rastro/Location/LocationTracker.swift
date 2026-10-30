import Foundation
import CoreLocation
import SwiftData

/// Owns the CLLocationManager and writes everything it hears into SwiftData.
///
/// Battery strategy: we never run continuous GPS. We use two low-power iOS services:
///  • Visit monitoring  → "you arrived at / left a place"
///  • Significant location changes → a point roughly every ~500 m of movement
/// Both keep working when the app is closed: iOS relaunches it in the background.
@MainActor
final class LocationTracker: NSObject, ObservableObject {
    static let shared = LocationTracker()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published var isTrackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTrackingEnabled, forKey: Self.trackingKey)
            isTrackingEnabled ? startIfAuthorized() : stop()
        }
    }

    private static let trackingKey = "trackingEnabled"
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var container: ModelContainer?

    private override init() {
        authorizationStatus = manager.authorizationStatus
        isTrackingEnabled = UserDefaults.standard.object(forKey: Self.trackingKey) as? Bool ?? true
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = false
    }

    func configure(container: ModelContainer) {
        self.container = container
        startIfAuthorized()
    }

    // MARK: Permissions

    /// iOS requires asking for "When In Use" first, then upgrading to "Always".
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

    var hasAlways: Bool { authorizationStatus == .authorizedAlways }
    var hasAnyPermission: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    // MARK: Start / stop

    private func startIfAuthorized() {
        guard isTrackingEnabled, hasAnyPermission else { return }
        if hasAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
        }
        manager.startMonitoringVisits()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    private func stop() {
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: Saving

    private func save(visit clVisit: CLVisit) {
        guard let context = container?.mainContext else { return }

        let arrival = clVisit.arrivalDate == .distantPast ? Date.now : clVisit.arrivalDate
        let departure: Date? = clVisit.departureDate == .distantFuture ? nil : clVisit.departureDate
        let coord = clVisit.coordinate

        // iOS reports a visit twice: on arrival (no departure yet) and on departure.
        // If we already have the open visit, just close it.
        let open = FetchDescriptor<Visit>(predicate: #Predicate { $0.departure == nil })
        if let existing = (try? context.fetch(open))?.first(where: {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) < 200
        }) {
            existing.departure = departure
            try? context.save()
            return
        }

        // Close any other dangling open visit (we clearly left it).
        if let dangling = try? context.fetch(open) {
            for v in dangling { v.departure = v.departure ?? arrival }
        }

        let visit = Visit(arrival: arrival, departure: departure,
                          latitude: coord.latitude, longitude: coord.longitude)
        context.insert(visit)
        try? context.save()
        geocode(visit)
    }

    private func save(points: [CLLocation]) {
        guard let context = container?.mainContext else { return }
        for loc in points where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 1_000 {
            context.insert(LocationPoint(timestamp: loc.timestamp,
                                         latitude: loc.coordinate.latitude,
                                         longitude: loc.coordinate.longitude,
                                         horizontalAccuracy: loc.horizontalAccuracy))
        }
        try? context.save()
    }

    /// Turns coordinates into "Café X, Walnut Creek, United States".
    private func geocode(_ visit: Visit) {
        let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let pm = placemarks?.first else { return }
            Task { @MainActor in
                visit.name = pm.areasOfInterest?.first ?? pm.name
                visit.locality = pm.locality
                visit.adminArea = pm.administrativeArea
                visit.country = pm.country
                try? self?.container?.mainContext.save()
            }
        }
    }

    /// Fills in names for visits recorded while offline / rate-limited.
    func geocodeMissing() {
        guard let context = container?.mainContext else { return }
        let missing = FetchDescriptor<Visit>(predicate: #Predicate { $0.locality == nil })
        let visits = (try? context.fetch(missing)) ?? []
        // CLGeocoder handles one request at a time and is rate-limited, so space them out.
        Task { @MainActor in
            for v in visits.prefix(20) {
                geocode(v)
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.startIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in self.save(visit: visit) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.save(points: locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
