import Foundation
import CoreLocation

enum RecapPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case allTime = "All"
    var id: String { rawValue }

    /// The calendar unit used to step back/forward through periods (nil = all time).
    var calendarComponent: Calendar.Component? {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .allTime: nil
        }
    }
}

/// All the numbers shown on the recap screen, computed from raw data.
struct RecapStats {
    struct TopPlace: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let totalTime: TimeInterval
        let visits: Int
        let coordinate: CLLocationCoordinate2D
    }

    let title: String
    let visits: [Visit]
    let points: [LocationPoint]
    let uniquePlaces: Int
    let cities: [String]
    let countries: [String]
    let distanceKm: Double
    let topPlaces: [TopPlace]
    let daysTracked: Int

    static func make(period: RecapPeriod, anchor: Date,
                     allVisits: [Visit], allPoints: [LocationPoint]) -> RecapStats {
        let cal = Calendar.current
        let interval: DateInterval?
        let title: String
        let fmt = DateFormatter()

        switch period {
        case .day:
            interval = cal.dateInterval(of: .day, for: anchor)
            if cal.isDateInToday(anchor) {
                title = "Today"
            } else if cal.isDateInYesterday(anchor) {
                title = "Yesterday"
            } else {
                fmt.dateFormat = "EEE, MMM d, yyyy"
                title = fmt.string(from: anchor)
            }
        case .week:
            interval = cal.dateInterval(of: .weekOfYear, for: anchor)
            if let w = interval {
                // end is exclusive (next week's start), so show the last day of this week
                let lastDay = w.end.addingTimeInterval(-1)
                fmt.dateFormat = "MMM d"
                let start = fmt.string(from: w.start)
                let sameMonth = cal.isDate(w.start, equalTo: lastDay, toGranularity: .month)
                fmt.dateFormat = sameMonth ? "d, yyyy" : "MMM d, yyyy"
                title = "\(start) – \(fmt.string(from: lastDay))"
            } else {
                title = "This week"
            }
        case .month:
            interval = cal.dateInterval(of: .month, for: anchor)
            fmt.dateFormat = "LLLL yyyy"
            title = fmt.string(from: anchor)
        case .year:
            interval = cal.dateInterval(of: .year, for: anchor)
            fmt.dateFormat = "yyyy"
            title = fmt.string(from: anchor)
        case .allTime:
            interval = nil
            title = "All time"
        }

        let visits = allVisits.filter { interval?.contains($0.arrival) ?? true }
        let points = allPoints.filter { interval?.contains($0.timestamp) ?? true }
            .sorted { $0.timestamp < $1.timestamp }

        // Distance: sum of hops between consecutive breadcrumbs + visit locations.
        let path = (points.map { ($0.timestamp, $0.location) } +
                    visits.map { ($0.arrival, CLLocation(latitude: $0.latitude, longitude: $0.longitude)) })
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        var meters = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            let d = b.distance(from: a)
            if d > 50 { meters += d }   // ignore GPS jitter
        }

        // Top places by total time spent.
        let grouped = Dictionary(grouping: visits, by: \.placeKey)
        let top = grouped.map { key, vs in
            TopPlace(id: key,
                     name: vs[0].displayName,
                     subtitle: [vs[0].locality, vs[0].country].compactMap { $0 }.joined(separator: ", "),
                     totalTime: vs.reduce(0) { $0 + $1.duration },
                     visits: vs.count,
                     coordinate: vs[0].coordinate)
        }
        .sorted { $0.totalTime > $1.totalTime }

        let days = Set((visits.map(\.arrival) + points.map(\.timestamp)).map { cal.startOfDay(for: $0) }).count

        return RecapStats(
            title: title,
            visits: visits,
            points: points,
            uniquePlaces: grouped.count,
            cities: Array(Set(visits.compactMap(\.locality))).sorted(),
            countries: Array(Set(visits.compactMap(\.country))).sorted(),
            distanceKm: meters / 1000,
            topPlaces: Array(top.prefix(10)),
            daysTracked: days
        )
    }
}

extension TimeInterval {
    var shortDuration: String {
        let f = DateComponentsFormatter()
        f.allowedUnits = self >= 86_400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: self) ?? "-"
    }
}
