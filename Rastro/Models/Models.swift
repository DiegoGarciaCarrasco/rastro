import Foundation
import SwiftData
import CoreLocation

/// A place where you stayed for a while (home, office, a café, a city you visited).
/// Comes from iOS's built-in visit detection (CLVisit), which is very battery friendly.
@Model
final class Visit {
    var arrival: Date
    var departure: Date?
    var latitude: Double
    var longitude: Double
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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// How long you stayed. Ongoing visits count up to "now".
    var duration: TimeInterval {
        (departure ?? .now).timeIntervalSince(arrival)
    }

    var displayName: String {
        name ?? locality ?? String(format: "%.4f, %.4f", latitude, longitude)
    }

    /// Groups nearby visits (~100 m) to the same place, for "top places".
    var placeKey: String {
        if let name, let locality { return "\(name)|\(locality)" }
        return String(format: "%.3f,%.3f", latitude, longitude)
    }
}

/// A raw breadcrumb point (from significant-location-change updates).
/// Used to draw your path and compute distance traveled.
@Model
final class LocationPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double

    init(timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
