//
//  HistoryView.swift
//  Rastro
//
//  HISTORY TAB — a diary-style list of every visit, newest day first.
//
//   • `HistoryView`     — the list, grouped into one section per day; swipe to delete.
//   • `VisitRow`        — one row: icon, place name, "10:05 – 11:40", duration.
//   • `VisitDetailView` — tap a row: small map + all details of that visit.
//
//  Reads Visits straight from the database with @Query (no LocationPoints here).
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - HistoryView

/// Day-by-day list of every place you stayed.
struct HistoryView: View {
    /// All visits, newest first. Auto-refreshes when the tracker saves a new one.
    @Query(sort: \Visit.arrival, order: .reverse) private var visits: [Visit]
    /// Database handle, needed here only for deleting.
    @Environment(\.modelContext) private var context

    /// Groups visits by calendar day (by ARRIVAL), days sorted newest first.
    /// Visits inside each day stay newest-first because `visits` is already sorted.
    private var byDay: [(day: Date, visits: [Visit])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: visits) { cal.startOfDay(for: $0.arrival) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(byDay, id: \.day) { group in
                    // Section header, e.g. "Thursday, November 26, 2026"
                    Section(group.day.formatted(.dateTime.weekday(.wide).month().day().year())) {
                        ForEach(group.visits) { visit in
                            NavigationLink { VisitDetailView(visit: visit) } label: {
                                VisitRow(visit: visit)
                            }
                        }
                        // Swipe-to-delete: `idx` are positions within THIS day's group.
                        .onDelete { idx in
                            idx.map { group.visits[$0] }.forEach(context.delete)
                            try? context.save()
                        }
                    }
                }
            }
            // Empty state on a fresh install.
            .overlay {
                if visits.isEmpty {
                    ContentUnavailableView("No visits yet", systemImage: "mappin.slash",
                        description: Text("Places show up here after you've stayed somewhere for a few minutes."))
                }
            }
            .navigationTitle("History")
        }
    }
}

// MARK: - VisitRow

/// One line in the history list.
struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            // Filled arrow = you're still there (open visit); pin = finished visit.
            Image(systemName: visit.departure == nil ? "location.fill" : "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text(timeRange).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(visit.duration.shortDuration).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// "10:05 – 11:40", or "10:05 – now" for an open visit.
    private var timeRange: String {
        let start = visit.arrival.formatted(date: .omitted, time: .shortened)
        guard let end = visit.departure else { return "\(start) – now" }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - VisitDetailView

/// Detail screen for one visit: zoomed-in map + labeled fields.
struct VisitDetailView: View {
    let visit: Visit

    var body: some View {
        List {
            // Map section (~1 km across, centered on the visit)
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: visit.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                    Marker(visit.displayName, coordinate: visit.coordinate).tint(.orange)
                }
                .frame(height: 220)
                .listRowInsets(EdgeInsets())   // edge-to-edge inside the list row
            }
            // Facts section (city / country rows only appear if geocoding found them)
            Section {
                LabeledContent("Place", value: visit.displayName)
                if let city = visit.locality { LabeledContent("City", value: city) }
                if let country = visit.country { LabeledContent("Country", value: country) }
                LabeledContent("Arrived", value: visit.arrival.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Left", value: visit.departure?.formatted(date: .abbreviated, time: .shortened) ?? "Still here")
                LabeledContent("Stayed", value: visit.duration.shortDuration)
            }
        }
        .navigationTitle(visit.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews (Xcode canvas only — open with ⌥⌘↩)

#if DEBUG
#Preview("History · sample data") {
    HistoryView()
        .modelContainer(PreviewData.container)
}

#Preview("History · empty") {
    HistoryView()
        .modelContainer(PreviewData.emptyContainer)
}

#Preview("Rows · finished vs. ongoing") {
    List {
        VisitRow(visit: PreviewData.sampleVisit)
        VisitRow(visit: PreviewData.openVisit)
    }
    .modelContainer(PreviewData.container)
}

#Preview("Visit detail") {
    NavigationStack {
        VisitDetailView(visit: PreviewData.sampleVisit)
    }
    .modelContainer(PreviewData.container)
}
#endif
