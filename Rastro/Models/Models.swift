//
//  Models.swift
//  Rastro
//
//  DATA MODEL — the only two things Rastro ever stores.
//
//   • `Visit`         — "you stayed at this place from A to B" (from iOS visit detection).
//   • `LocationPoint` — a raw breadcrumb "you were here at time T" (from significant
//                       location changes). Used for the path line and km traveled.
//
//  `@Model` (SwiftData) turns a plain class into a database table: every stored `var`
//  becomes a column, and SwiftUI views that `@Query` these types refresh automatically
//  when rows are inserted, changed or deleted.
//
//  Computed properties (`coordinate`, `duration`, `displayName`, `placeKey`, `location`)
//  are NOT stored — they're derived on the fly from the stored fields.
//
//  Who writes these:  Location/LocationTracker.swift (inserts + geocoding updates),
//                     Views/HistoryView.swift and Views/SettingsView.swift (deletes).
//  Who reads these:   every screen, and Recap/RecapStats.swift for the math.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - Visit

/// A place where you stayed for a while (home, office, a café, a city you visited).
/// Comes from iOS's built-in visit detection (CLVisit), which is very battery friendly.
///
/// Lifecycle of one Visit:
///  1. iOS reports "arrived" → a Visit is inserted with `departure == nil` (an *open* visit).
///  2. Reverse geocoding fills in `name` / `locality` / `adminArea` / `country` a moment later.
///  3. iOS reports "departed" → the same Visit gets its `departure` date (now *closed*).
@Model
final class Visit {
    // MARK: Stored fields (saved in the database)

    var arrival: Date
    var departure: Date?     // nil = you're still there (open visit)
    var latitude: Double
    var longitude: Double

    // Filled in later by reverse geocoding; nil until then (or if offline / no result).
    var name: String?        // e.g. "Starbucks", "123 Main St"
    var locality: String?    // city
    var adminArea: String?   // state / region
    var country: String?

    init(arrival: Date, departure: Date?, latitude: Double, longitude: Double) {
        self.arrival = arrival
        self.departure = departure
        self.latitude = latitude
        self.longitude = longitude
    }

    // MARK: Derived helpers (not stored)

    /// Lat/long packed into the type MapKit wants for pins.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// How long you stayed. Ongoing visits count up to "now".
    var duration: TimeInterval {
        (departure ?? .now).timeIntervalSince(arrival)
    }

    /// Best human-readable label: place name → city → raw coordinates as a last resort.
    var displayName: String {
        name ?? locality ?? String(format: "%.4f, %.4f", latitude, longitude)
    }

    /// Groups nearby visits (~100 m) to the same place, for "top places".
    ///
    /// Two strategies:
    ///  • Geocoded: "Starbucks|Madrid" — same name in the same city = same place.
    ///  • Not geocoded: coordinates rounded to 3 decimals (≈110 m grid cell).
    /// NOTE: a visit's key changes once geocoding finishes, and two visits to the same
    /// spot can land on different sides of a grid-cell edge. Fine for v1; a distance-based
    /// clustering would be more accurate.
    var placeKey: String {
        if let name, let locality { return "\(name)|\(locality)" }
        return String(format: "%.3f,%.3f", latitude, longitude)
    }
}

// MARK: - LocationPoint

/// A raw breadcrumb point (from significant-location-change updates).
/// Used to draw your path and compute distance traveled.
///
/// iOS delivers these roughly every ~500 m of movement (more often in cities with
/// dense cell towers / Wi-Fi). They're never edited after being inserted.
@Model
final class LocationPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Radius of uncertainty in meters (smaller = more precise). Points worse than 1 km
    /// are already filtered out by LocationTracker before saving.
    var horizontalAccuracy: Double

    init(timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }

    /// For drawing on a MapKit map (polyline).
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// For distance math (`CLLocation.distance(from:)` returns meters).
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
