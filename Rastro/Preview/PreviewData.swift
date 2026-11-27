//
//  PreviewData.swift
//  Rastro
//
//  FAKE DATA FOR XCODE PREVIEWS ONLY. This file never ships in the App Store build.
//
//  Real Rastro screens show visits that iOS recorded over days. In Xcode's preview canvas
//  no tracking runs and the real database isn't used, so every screen would just say
//  "Nothing yet". This file builds a throwaway database that lives in memory and fills it
//  with a believable week of made-up data:
//
//   • Last 7 days in Madrid: home every night → café → office (the office visit
//     happening "now" is still open, shown as "Still here"), plus a park on some days.
//   • One visit with no place name, to show what an un-geocoded visit looks like.
//   • A weekend trip to Lisbon ending ~9 days ago, and a trip to Valencia ~7 months ago,
//     so the Year / All tabs show several cities and two countries. The Month tab
//     includes Lisbon from about the 12th of the month onward (dates are relative to
//     today, so early in a month the trip falls in the previous month).
//   • Path breadcrumbs (LocationPoints) between consecutive visits, so the map draws a
//     line and "km traveled" is not zero.
//
//  All dates are relative to "now", so the Day / Week tabs always have data whenever
//  you open the preview.
//
//  How previews use it (see the `#Preview` blocks at the bottom of each view file):
//      SomeView()
//          .modelContainer(PreviewData.container)          // with sample data
//          .modelContainer(PreviewData.emptyContainer)     // empty-state screens
//          .environmentObject(LocationTracker.shared)      // views that read permission state
//
//  `#if DEBUG` = compiled only in Debug builds (what Xcode uses for previews and for
//  running on your phone), and left out of Release / App Store archives.
//

#if DEBUG
import Foundation
import SwiftData

@MainActor
enum PreviewData {

    // MARK: - Ready-made containers

    /// In-memory database pre-filled with the sample week. Built once, shared by all previews.
    static let container: ModelContainer = {
        let container = makeInMemoryContainer()
        insertSampleData(into: container.mainContext)
        return container
    }()

    /// In-memory database with nothing in it, for previewing empty states.
    static var emptyContainer: ModelContainer { makeInMemoryContainer() }

    // MARK: - Ready-made single values

    /// One finished, geocoded visit (the most recent café stop) for detail/row previews.
    static var sampleVisit: Visit {
        allVisits.last { $0.departure != nil && $0.name != nil } ?? allVisits[0]
    }

    /// The visit happening right now (no departure), for the "still here" look.
    static var openVisit: Visit {
        allVisits.first { $0.departure == nil } ?? allVisits[0]
    }

    /// Recap numbers for the current month, for the share card / map previews.
    static func stats(_ period: RecapPeriod = .month) -> RecapStats {
        RecapStats.make(period: period, anchor: .now,
                        allVisits: allVisits, allPoints: allPoints)
    }

    // MARK: - Reading back what's stored

    private static var allVisits: [Visit] {
        let all = (try? container.mainContext.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrival)]))) ?? []
        return all
    }

    private static var allPoints: [LocationPoint] {
        (try? container.mainContext.fetch(FetchDescriptor<LocationPoint>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
    }

    // MARK: - Building the database

    /// Same two tables as the real app, but `isStoredInMemoryOnly` = nothing is written to disk.
    private static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: Visit.self, LocationPoint.self, configurations: config)
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }

    /// A named place we can reuse for many visits.
    private struct Place {
        let name: String?
        let city: String?
        let region: String?
        let country: String?
        let lat: Double
        let lon: Double
    }

    // Madrid
    private static let home    = Place(name: "Calle de Alcalá 120", city: "Madrid", region: "Madrid", country: "Spain", lat: 40.4237, lon: -3.6725)
    private static let office  = Place(name: "Paseo de la Castellana 81", city: "Madrid", region: "Madrid", country: "Spain", lat: 40.4483, lon: -3.6913)
    private static let cafe    = Place(name: "Café Central", city: "Madrid", region: "Madrid", country: "Spain", lat: 40.4146, lon: -3.7006)
    private static let park    = Place(name: "Retiro Park", city: "Madrid", region: "Madrid", country: "Spain", lat: 40.4153, lon: -3.6845)
    /// Not geocoded yet → shows as raw coordinates in the UI.
    private static let unnamed = Place(name: nil, city: nil, region: nil, country: nil, lat: 40.4380, lon: -3.7150)
    // Lisbon trip
    private static let lisbonHotel  = Place(name: "Hotel Avenida", city: "Lisbon", region: "Lisbon", country: "Portugal", lat: 38.7196, lon: -9.1450)
    private static let timeOut      = Place(name: "Time Out Market", city: "Lisbon", region: "Lisbon", country: "Portugal", lat: 38.7071, lon: -9.1459)
    private static let belem        = Place(name: "Belém Tower", city: "Lisbon", region: "Lisbon", country: "Portugal", lat: 38.6916, lon: -9.2160)
    // Valencia trip
    private static let valenciaBeach = Place(name: "Malvarrosa Beach", city: "Valencia", region: "Valencian Community", country: "Spain", lat: 39.4783, lon: -0.3238)
    private static let ciudadArtes   = Place(name: "City of Arts and Sciences", city: "Valencia", region: "Valencian Community", country: "Spain", lat: 39.4547, lon: -0.3502)

    /// Inserts every sample visit, then path points between them.
    private static func insertSampleData(into context: ModelContext) {
        let now = Date.now
        let hour: TimeInterval = 3_600
        let day: TimeInterval = 86_400
        var visits: [Visit] = []

        /// Adds one visit. `from` / `to` are offsets in hours relative to `base`;
        /// `to == nil` makes it an open (ongoing) visit.
        func add(_ place: Place, base: Date, from: Double, to: Double?) {
            let visit = Visit(arrival: base.addingTimeInterval(from * hour),
                              departure: to.map { base.addingTimeInterval($0 * hour) },
                              latitude: place.lat, longitude: place.lon)
            visit.name = place.name
            visit.locality = place.city
            visit.adminArea = place.region
            visit.country = place.country
            context.insert(visit)
            visits.append(visit)
        }

        // ── Last 7 days in Madrid. Hours are relative to "this moment, d days ago". ──
        for d in stride(from: 6, through: 0, by: -1) {
            let base = now.addingTimeInterval(-Double(d) * day)
            add(home, base: base, from: -16, to: -6)              // overnight at home
            add(cafe, base: base, from: -5.5, to: -5)             // morning coffee
            if d == 0 {
                add(office, base: base, from: -4.5, to: nil)      // at the office right now
            } else {
                add(office, base: base, from: -4.5, to: -1)
                if d % 2 == 0 { add(park, base: base, from: -0.5, to: 1) }   // evening walk
                if d == 3 { add(unnamed, base: base, from: 1.5, to: 2.5) }   // no name yet
            }
        }

        // ── Weekend in Lisbon, ending ~9 days ago (just before the Madrid week) ──
        // Kept recent so the Month tab includes it on most days of the month
        // (from about the 12th onward; earlier, it falls in the previous month).
        let lisbon = now.addingTimeInterval(-9 * day)
        add(lisbonHotel, base: lisbon, from: -40, to: -28)
        add(belem, base: lisbon, from: -27, to: -24)
        add(timeOut, base: lisbon, from: -23, to: -21)
        add(lisbonHotel, base: lisbon, from: -20, to: -8)

        // ── Trip to Valencia, ~7 months ago ──
        let valencia = now.addingTimeInterval(-210 * day)
        add(ciudadArtes, base: valencia, from: 0, to: 3)
        add(valenciaBeach, base: valencia, from: 4, to: 8)

        // ── Breadcrumbs: 4 points evenly spaced between each visit and the next ──
        // Only for gaps under 12 hours (one journey). Between trips weeks apart we'd
        // otherwise draw fake straight lines across the country and inflate km traveled.
        let ordered = visits.sorted { $0.arrival < $1.arrival }
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            let leave = a.departure ?? a.arrival
            let gap = b.arrival.timeIntervalSince(leave)
            guard gap > 0, gap < 12 * hour else { continue }
            for step in 1...4 {
                let f = Double(step) / 5
                context.insert(LocationPoint(
                    timestamp: leave.addingTimeInterval(gap * f),
                    latitude: a.latitude + (b.latitude - a.latitude) * f,
                    longitude: a.longitude + (b.longitude - a.longitude) * f,
                    horizontalAccuracy: 65))
            }
        }

        try? context.save()
    }
}
#endif
