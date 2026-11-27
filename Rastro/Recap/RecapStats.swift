//
//  RecapStats.swift
//  Rastro
//
//  RECAP MATH — pure calculation, no UI, no database writes.
//
//  Input:  a period (Day/Week/Month/Year/All), an "anchor" date inside that period,
//          and ALL visits + points from the database.
//  Output: one `RecapStats` value with everything the Recap screen and share card show:
//          title, filtered visits/points, unique places, cities, countries, km traveled,
//          top 10 places, days tracked.
//
//  Because it's a plain function of its inputs, this is the easiest part of the app to
//  unit-test (feed it fake visits, check the numbers).
//
//  Used by: Recap/RecapView.swift (computes it), Recap/ShareRecap.swift (renders it).
//

import Foundation
import CoreLocation

// MARK: - RecapPeriod

/// The segmented control on the Recap screen. `rawValue` is the label shown to the user.
enum RecapPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case allTime = "All"
    var id: String { rawValue }   // Identifiable → usable directly in ForEach

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

// MARK: - RecapStats

/// All the numbers shown on the recap screen, computed from raw data.
struct RecapStats {
    /// One row of "Where you spent your time": several visits to the same place merged.
    struct TopPlace: Identifiable {
        let id: String                       // the Visit.placeKey shared by the group
        let name: String
        let subtitle: String                 // "City, Country"
        let totalTime: TimeInterval          // sum of all visit durations
        let visits: Int                      // how many separate visits
        let coordinate: CLLocationCoordinate2D
    }

    let title: String              // "Today", "Nov 23 – 29, 2026", "March 2026", "2026", "All time"
    let visits: [Visit]            // visits that ARRIVED inside the period
    let points: [LocationPoint]    // breadcrumbs inside the period, oldest first
    let uniquePlaces: Int          // distinct placeKeys
    let cities: [String]           // distinct, alphabetical
    let countries: [String]        // distinct, alphabetical
    let distanceKm: Double
    let topPlaces: [TopPlace]      // max 10, most time first
    let daysTracked: Int           // distinct calendar days with any data (not shown in UI yet)

    /// Builds the stats for one period. Runs on every redraw of RecapView.
    static func make(period: RecapPeriod, anchor: Date,
                     allVisits: [Visit], allPoints: [LocationPoint]) -> RecapStats {
        let cal = Calendar.current
        let interval: DateInterval?   // nil = no filtering (all time)
        let title: String
        let fmt = DateFormatter()

        // ── Step 1: work out the date range and the title for the chosen period ──
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
            // Week start (Sunday/Monday) follows the user's region settings.
            interval = cal.dateInterval(of: .weekOfYear, for: anchor)
            if let w = interval {
                // end is exclusive (next week's start), so show the last day of this week
                let lastDay = w.end.addingTimeInterval(-1)
                fmt.dateFormat = "MMM d"
                let start = fmt.string(from: w.start)
                // "Nov 23 – 29, 2026" vs "Nov 30 – Dec 6, 2026"
                let sameMonth = cal.isDate(w.start, equalTo: lastDay, toGranularity: .month)
                fmt.dateFormat = sameMonth ? "d, yyyy" : "MMM d, yyyy"
                title = "\(start) – \(fmt.string(from: lastDay))"
            } else {
                title = "This week"
            }
        case .month:
            interval = cal.dateInterval(of: .month, for: anchor)
            fmt.dateFormat = "LLLL yyyy"   // "LLLL" = standalone month name, e.g. "November"
            title = fmt.string(from: anchor)
        case .year:
            interval = cal.dateInterval(of: .year, for: anchor)
            fmt.dateFormat = "yyyy"
            title = fmt.string(from: anchor)
        case .allTime:
            interval = nil
            title = "All time"
        }

        // ── Step 2: keep only the data inside the range ──
        // A visit belongs to the period it STARTED in (an overnight stay counts for day 1).
        let visits = allVisits.filter { interval?.contains($0.arrival) ?? true }
        let points = allPoints.filter { interval?.contains($0.timestamp) ?? true }
            .sorted { $0.timestamp < $1.timestamp }

        // ── Step 3: distance traveled ──
        // Merge breadcrumbs and visit locations into one timeline, then add up the
        // straight-line distance between each consecutive pair.
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

        // ── Step 4: top places ──
        // Group visits by placeKey, sum their durations, sort by most time.
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

        // ── Step 5: number of distinct days that have any data ──
        let days = Set((visits.map(\.arrival) + points.map(\.timestamp)).map { cal.startOfDay(for: $0) }).count

        // ── Step 6: package everything up ──
        return RecapStats(
            title: title,
            visits: visits,
            points: points,
            uniquePlaces: grouped.count,
            cities: Array(Set(visits.compactMap(\.locality))).sorted(),     // Set = remove duplicates
            countries: Array(Set(visits.compactMap(\.country))).sorted(),
            distanceKm: meters / 1000,
            topPlaces: Array(top.prefix(10)),
            daysTracked: days
        )
    }
}

// MARK: - Formatting helper

extension TimeInterval {
    /// Compact duration text: "45m", "3h 20m", "2d 4h" (≥ 1 day switches to days + hours).
    var shortDuration: String {
        let f = DateComponentsFormatter()
        f.allowedUnits = self >= 86_400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: self) ?? "-"
    }
}
