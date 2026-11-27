//
//  VisitRecorder.swift
//  Rastro
//
//  VISIT BOOKKEEPING — turns iOS visit events into correct `Visit` rows.
//
//  iOS's visit events are messy:
//   • Each stay is reported TWICE: once on arrival (no departure yet) and once on
//     departure (same arrival date, now with a departure date).
//   • Events can be missing (a departure never arrives), late (the departure from A
//     arrives after you've already arrived at B), or repeated.
//   • The arrival time can be unknown (`distantPast`), e.g. after a background relaunch.
//
//  This type holds all the rules for handling that, and nothing else: no CoreLocation
//  manager, no UI, no network. `LocationTracker` hands it each event; tests in
//  RastroTests/VisitRecorderTests.swift feed it fake events with an in-memory database.
//
//  The rules, in order (see `record(_:in:)`):
//   0. Ignore nonsense: no dates at all, or departure before arrival.
//   1. Same stay already saved?  (same arrival time ± 5 min, within 200 m)
//        → update its departure. Never insert a duplicate.
//   2. Departure with unknown arrival?  → close the open visit here, if there is one.
//   3. Otherwise it's a new stay:
//        → close any older open visits (they were clearly left), using the first
//          breadcrumb that shows you moving away as their departure time when we have one;
//        → insert the new visit.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - VisitEvent

/// One iOS visit event in plain values (no `CLVisit`), so tests can create them freely.
struct VisitEvent {
    var arrival: Date?      // nil = iOS doesn't know when you arrived
    var departure: Date?    // nil = you're still there
    var latitude: Double
    var longitude: Double

    init(arrival: Date?, departure: Date?, latitude: Double, longitude: Double) {
        self.arrival = arrival
        self.departure = departure
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Translates iOS's sentinel dates into optionals:
    /// `distantPast` arrival = unknown, `distantFuture` departure = still there.
    init(_ visit: CLVisit) {
        self.init(arrival: visit.arrivalDate == .distantPast ? nil : visit.arrivalDate,
                  departure: visit.departureDate == .distantFuture ? nil : visit.departureDate,
                  latitude: visit.coordinate.latitude,
                  longitude: visit.coordinate.longitude)
    }
}

// MARK: - VisitRecorder

@MainActor
enum VisitRecorder {

    // MARK: Tuning values

    /// Two events closer than this are treated as the same place.
    static let samePlaceRadius: CLLocationDistance = 200
    /// Two arrival times closer than this are treated as the same stay.
    static let sameArrivalTolerance: TimeInterval = 5 * 60

    // MARK: Recording

    /// Applies one iOS visit event to the database.
    /// - Returns: the newly inserted visit (so the caller can look up its name),
    ///   or nil if the event only updated an existing visit or was ignored.
    @discardableResult
    static func record(_ event: VisitEvent, in context: ModelContext) -> Visit? {
        // ── Rule 0: ignore nonsense ──
        if let arrival = event.arrival, let departure = event.departure, departure < arrival {
            return nil
        }
        guard let start = event.arrival ?? event.departure else { return nil }   // no dates at all

        let here = CLLocation(latitude: event.latitude, longitude: event.longitude)

        // ── Rule 1: the same stay is already saved → just update its departure ──
        // Matching on arrival time (not only "is there an open visit nearby?") is what
        // keeps a new arrival at home from being merged into yesterday's home visit,
        // and lets a late departure find its visit even after it was closed as stale.
        if let arrival = event.arrival,
           let existing = visit(arrivingAround: arrival, near: here, in: context) {
            if let departure = event.departure {
                existing.departure = departure
            }
            try? context.save()
            return nil
        }

        // ── Rule 2: departure with an unknown arrival → close the open visit here ──
        if event.arrival == nil, let departure = event.departure,
           let existing = openVisits(in: context)
               .filter({ $0.arrival <= departure && isNear($0, here) })
               .max(by: { $0.arrival < $1.arrival }) {
            existing.departure = departure
            try? context.save()
            return nil
        }

        // ── Rule 3: a new stay ──
        // Any visit still open from before this one was clearly left: close it.
        for stale in openVisits(in: context) where stale.arrival < start {
            stale.departure = leftTime(of: stale, before: start, in: context)
        }
        // Unknown arrival → we only know when you left, so record a zero-length visit
        // at the departure time (never a negative duration).
        let visit = Visit(arrival: start, departure: event.departure,
                          latitude: event.latitude, longitude: event.longitude)
        context.insert(visit)
        try? context.save()
        return visit
    }

    // MARK: Helpers

    /// When did you leave `visit`? The first breadcrumb after its arrival that is farther
    /// than `samePlaceRadius` from it, or `fallback` if there's no such breadcrumb.
    /// Without this, a visit whose departure iOS never sent would last until your next
    /// arrival anywhere (e.g. "home" until the next evening).
    static func leftTime(of visit: Visit, before fallback: Date, in context: ModelContext) -> Date {
        let from = visit.arrival
        let descriptor = FetchDescriptor<LocationPoint>(
            predicate: #Predicate { $0.timestamp > from && $0.timestamp < fallback },
            sortBy: [SortDescriptor(\.timestamp)])
        let points = (try? context.fetch(descriptor)) ?? []
        let place = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        let firstAway = points.first { $0.location.distance(from: place) > samePlaceRadius }
        return firstAway?.timestamp ?? fallback
    }

    /// A saved visit with (almost) this arrival time at (almost) this place, open or closed.
    private static func visit(arrivingAround arrival: Date, near here: CLLocation,
                              in context: ModelContext) -> Visit? {
        let lo = arrival.addingTimeInterval(-sameArrivalTolerance)
        let hi = arrival.addingTimeInterval(sameArrivalTolerance)
        let descriptor = FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival >= lo && $0.arrival <= hi })
        return ((try? context.fetch(descriptor)) ?? []).first { isNear($0, here) }
    }

    /// Every visit that has no departure yet.
    private static func openVisits(in context: ModelContext) -> [Visit] {
        (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.departure == nil }))) ?? []
    }

    private static func isNear(_ visit: Visit, _ here: CLLocation) -> Bool {
        CLLocation(latitude: visit.latitude, longitude: visit.longitude).distance(from: here) < samePlaceRadius
    }

    // MARK: Lookup that survives deletion

    /// Re-fetches a visit by its database ID. Returns nil if it has been deleted.
    /// Used after any `await` (e.g. geocoding), because the user may delete the visit
    /// while we wait, and writing to a deleted model can crash or bring it back.
    static func liveVisit(_ id: PersistentIdentifier, in context: ModelContext) -> Visit? {
        var descriptor = FetchDescriptor<Visit>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
