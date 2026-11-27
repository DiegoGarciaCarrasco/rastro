//
//  RecapStatsTests.swift
//  RastroTests
//
//  Tests for the recap math in Rastro/Recap/RecapStats.swift: worked examples of
//  "these visits and points give these numbers". A first set; add more as the
//  recaps grow.
//

import Testing
import Foundation
import SwiftData
@testable import Rastro

@MainActor
struct RecapStatsTests {

    // Visits and points are SwiftData models, so they need a container to live in.
    let container: ModelContainer

    init() throws {
        container = try ModelContainer(for: Visit.self, LocationPoint.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    let now = Date.now

    func visit(_ name: String, city: String, country: String,
               lat: Double, lon: Double, hoursAgo: Double, stay: Double) -> Visit {
        let arrival = now.addingTimeInterval(-hoursAgo * 3_600)
        let v = Visit(arrival: arrival, departure: arrival.addingTimeInterval(stay * 3_600),
                      latitude: lat, longitude: lon)
        v.name = name
        v.locality = city
        v.country = country
        container.mainContext.insert(v)
        return v
    }

    @Test("All time counts unique places, cities and countries, and ranks by time spent")
    func allTimeTotals() {
        let visits = [
            visit("Cafe", city: "Madrid", country: "Spain", lat: 40.41, lon: -3.70, hoursAgo: 10, stay: 1),
            visit("Cafe", city: "Madrid", country: "Spain", lat: 40.41, lon: -3.70, hoursAgo: 5, stay: 1),
            visit("Office", city: "Madrid", country: "Spain", lat: 40.45, lon: -3.69, hoursAgo: 4, stay: 3),
            visit("Market", city: "Lisbon", country: "Portugal", lat: 38.71, lon: -9.15, hoursAgo: 400, stay: 1),
        ]
        let stats = RecapStats.make(period: .allTime, anchor: now, allVisits: visits, allPoints: [])

        #expect(stats.uniquePlaces == 3)                        // two cafe visits = one place
        #expect(stats.cities == ["Lisbon", "Madrid"])           // sorted, no duplicates
        #expect(stats.countries == ["Portugal", "Spain"])
        #expect(stats.topPlaces.first?.name == "Office")        // 3 h beats the cafe's 2 h
        #expect(stats.topPlaces.first(where: { $0.name == "Cafe" })?.visits == 2)
    }

    @Test("Moves under 50 m are ignored as GPS jitter")
    func jitterIgnored() {
        let a = LocationPoint(timestamp: now.addingTimeInterval(-60), latitude: 40.4000, longitude: -3.7000, horizontalAccuracy: 10)
        let b = LocationPoint(timestamp: now, latitude: 40.4002, longitude: -3.7000, horizontalAccuracy: 10)   // ~22 m
        let stats = RecapStats.make(period: .allTime, anchor: now, allVisits: [], allPoints: [a, b])
        #expect(stats.distanceKm == 0)
    }

    @Test("Distance adds up hops between consecutive points")
    func distanceAddsUp() {
        // 0.01° of latitude ≈ 1.11 km.
        let a = LocationPoint(timestamp: now.addingTimeInterval(-120), latitude: 40.40, longitude: -3.70, horizontalAccuracy: 10)
        let b = LocationPoint(timestamp: now.addingTimeInterval(-60), latitude: 40.41, longitude: -3.70, horizontalAccuracy: 10)
        let c = LocationPoint(timestamp: now, latitude: 40.42, longitude: -3.70, horizontalAccuracy: 10)
        let stats = RecapStats.make(period: .allTime, anchor: now, allVisits: [], allPoints: [a, b, c])
        #expect(abs(stats.distanceKm - 2.22) < 0.05)
    }

    @Test("The Day period only includes visits that arrived that day")
    func dayFilter() {
        let today = visit("Cafe", city: "Madrid", country: "Spain", lat: 40.41, lon: -3.70, hoursAgo: 0.5, stay: 0.25)
        let lastWeek = visit("Office", city: "Madrid", country: "Spain", lat: 40.45, lon: -3.69, hoursAgo: 24 * 8, stay: 3)
        // Anchor on the visit itself, so the test also passes when run just after midnight.
        let stats = RecapStats.make(period: .day, anchor: today.arrival, allVisits: [today, lastWeek], allPoints: [])
        #expect(stats.visits.count == 1)
        #expect(stats.visits.first?.name == "Cafe")
    }
}
