//
//  VisitRecorderTests.swift
//  RastroTests
//
//  Tests for the visit merge rules in Rastro/Location/VisitRecorder.swift.
//
//  Each test builds a fresh in-memory database, feeds VisitRecorder a sequence of fake
//  iOS visit events, and checks the visits that end up saved. Every bug found in the
//  code review has a test named after it, so it can't come back unnoticed.
//
//  Run: ⌘U in Xcode, or
//  xcodebuild test -project Rastro.xcodeproj -scheme Rastro -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
//

import Testing
import Foundation
import SwiftData
@testable import Rastro

@MainActor
struct VisitRecorderTests {

    // MARK: Test helpers

    let context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Visit.self, LocationPoint.self, configurations: config)
        context = ModelContext(container)
    }

    // Two places ~3 km apart in Madrid.
    let home = (lat: 40.4237, lon: -3.6725)
    let office = (lat: 40.4483, lon: -3.6913)

    /// A fixed starting time, so tests don't depend on the clock.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(hours: Double) -> Date { t0.addingTimeInterval(hours * 3_600) }

    func event(_ place: (lat: Double, lon: Double), arrival: Date?, departure: Date?) -> VisitEvent {
        VisitEvent(arrival: arrival, departure: departure, latitude: place.lat, longitude: place.lon)
    }

    func allVisits() throws -> [Visit] {
        try context.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrival)]))
    }

    // MARK: Normal case

    @Test("Arrival then departure of the same stay gives one closed visit")
    func arrivalThenDeparture() throws {
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: at(hours: 8)), in: context)

        let visits = try allVisits()
        #expect(visits.count == 1)
        #expect(visits[0].departure == at(hours: 8))
    }

    @Test("A repeated arrival event doesn't create a duplicate")
    func repeatedArrival() throws {
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        #expect(try allVisits().count == 1)
    }

    @Test("Only a new stay is returned, so only new stays get geocoded")
    func returnValue() {
        let first = VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        let update = VisitRecorder.record(event(home, arrival: at(hours: 0), departure: at(hours: 1)), in: context)
        #expect(first != nil)
        #expect(update == nil)
    }

    // MARK: Review bug 1 — a new arrival merged into an old open visit

    @Test("Coming home the next day creates a new visit instead of reusing yesterday's")
    func newArrivalAtSamePlace() throws {
        // Yesterday's departure from home was never delivered.
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        // Next evening, you arrive home again.
        VisitRecorder.record(event(home, arrival: at(hours: 24), departure: nil), in: context)

        let visits = try allVisits()
        #expect(visits.count == 2)
        #expect(visits[0].departure != nil)   // the old one got closed
        #expect(visits[1].departure == nil)   // the new one is open
    }

    @Test("A stale visit is closed when breadcrumbs show you leaving, not at the next arrival")
    func staleVisitUsesBreadcrumbs() throws {
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        // A breadcrumb 3 km away at hour 9 shows you had left home by then.
        context.insert(LocationPoint(timestamp: at(hours: 9), latitude: office.lat,
                                     longitude: office.lon, horizontalAccuracy: 50))
        VisitRecorder.record(event(home, arrival: at(hours: 24), departure: nil), in: context)

        #expect(try allVisits()[0].departure == at(hours: 9))
    }

    // MARK: Review bug 2 — late departure creating a duplicate

    @Test("A departure that arrives after the next arrival updates the right visit")
    func lateDeparture() throws {
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        VisitRecorder.record(event(office, arrival: at(hours: 9), departure: nil), in: context)   // closes home as stale
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: at(hours: 8.5)), in: context)   // late

        let visits = try allVisits()
        #expect(visits.count == 2)                       // no duplicate home visit
        #expect(visits[0].departure == at(hours: 8.5))   // real departure time, not the stale guess
    }

    // MARK: Review bug 4 — negative durations

    @Test("A departure with an unknown arrival never creates a negative duration")
    func unknownArrivalNoMatch() throws {
        VisitRecorder.record(event(home, arrival: nil, departure: at(hours: 8)), in: context)

        let visits = try allVisits()
        #expect(visits.count == 1)
        #expect(visits[0].arrival == at(hours: 8))
        #expect(visits[0].duration == 0)
    }

    @Test("A departure with an unknown arrival closes the open visit at that place")
    func unknownArrivalClosesOpenVisit() throws {
        VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context)
        VisitRecorder.record(event(home, arrival: nil, departure: at(hours: 8)), in: context)

        let visits = try allVisits()
        #expect(visits.count == 1)
        #expect(visits[0].departure == at(hours: 8))
    }

    @Test("An event whose departure is before its arrival is ignored")
    func departureBeforeArrival() throws {
        VisitRecorder.record(event(home, arrival: at(hours: 8), departure: at(hours: 7)), in: context)
        #expect(try allVisits().isEmpty)
    }

    @Test("Duration is never negative, even for bad rows saved by older versions")
    func durationClamp() {
        let bad = Visit(arrival: at(hours: 2), departure: at(hours: 1), latitude: 0, longitude: 0)
        #expect(bad.duration == 0)
    }

    // MARK: Review bug 3 — writing to a deleted visit

    @Test("liveVisit finds a visit by ID, and returns nil once it's deleted")
    func liveVisitAfterDelete() throws {
        let visit = try #require(VisitRecorder.record(event(home, arrival: at(hours: 0), departure: nil), in: context))
        let id = visit.persistentModelID
        #expect(VisitRecorder.liveVisit(id, in: context) != nil)

        context.delete(visit)
        try context.save()
        #expect(VisitRecorder.liveVisit(id, in: context) == nil)
    }
}
