//
//  RecapView.swift
//  Rastro
//
//  RECAP TAB — the main screen of the app.
//
//  Layout (top → bottom):
//   ┌───────────────────────────────┐
//   │ "Allow Always" banner (if needed) │  ← AlwaysPermissionBanner (OnboardingView.swift)
//   │ [Day|Week|Month|Year|All]      │  ← period picker
//   │  ‹   November 2026   ›         │  ← periodStepper
//   │ ┌───────── map ─────────┐      │  ← RecapMap (path + top places)
//   │ [Places][Traveled]             │  ← statGrid / StatTile
//   │ [Cities][Countries]            │
//   │ Countries: chips…  Cities: chips… │  ← chipSection
//   │ 1. Home …  2. Office …         │  ← topPlaces
//   └───────────────────────────────┘
//   Toolbar: share button → ShareRecap.swift
//
//  Data flow: @Query loads ALL visits + points → `RecapStats.make` filters them to the
//  selected period → the pieces below just display the result.
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - RecapView

struct RecapView: View {
    // Live database queries: SwiftUI re-renders this view whenever rows change.
    @Query(sort: \Visit.arrival) private var visits: [Visit]
    @Query(sort: \LocationPoint.timestamp) private var points: [LocationPoint]

    // Screen state: which kind of period, and a date that falls inside the one shown.
    // e.g. period = .month, anchor = Oct 15 → "October 2026".
    @State private var period: RecapPeriod = .month
    @State private var anchor: Date = .now

    /// Recomputed on every redraw. NOTE: fine for now, but with years of breadcrumbs this
    /// filters everything in memory each time — a date-ranged @Query would scale better.
    private var stats: RecapStats {
        RecapStats.make(period: period, anchor: anchor, allVisits: visits, allPoints: points)
    }

    var body: some View {
        let stats = self.stats   // compute once per redraw, reuse below
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AlwaysPermissionBanner()

                    // Period selector
                    Picker("Period", selection: $period) {
                        ForEach(RecapPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // Jump back to the current day/week/month/year when switching tabs
                    .onChange(of: period) { _, _ in anchor = .now }

                    // ‹ title › navigation
                    periodStepper(title: stats.title)

                    if stats.visits.isEmpty && stats.points.isEmpty {
                        // Empty state (new install, or a period with no data)
                        ContentUnavailableView("Nothing yet",
                            systemImage: "figure.walk",
                            description: Text("Go places! Rastro records visits automatically. Check back in a day or two."))
                            .padding(.top, 40)
                    } else {
                        // Map of the period
                        RecapMap(stats: stats)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        // 2×2 stat tiles
                        statGrid(stats)

                        // Chip rows
                        if !stats.countries.isEmpty {
                            chipSection(title: "Countries", items: stats.countries, icon: "globe.americas.fill")
                        }
                        if !stats.cities.isEmpty {
                            chipSection(title: "Cities", items: stats.cities, icon: "building.2.fill")
                        }

                        // Ranked list
                        topPlaces(stats)
                    }
                }
                .padding()
            }
            .navigationTitle("Recap")
            .toolbar {
                // Share button only when there's something to share.
                if !stats.visits.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareRecapButton(stats: stats)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    /// "‹  November 2026  ›" — hidden for All time. The › button is disabled on the
    /// current period so you can't browse into the future.
    @ViewBuilder
    private func periodStepper(title: String) -> some View {
        if period != .allTime {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(title)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentPeriod)
            }
            .padding(.horizontal, 4)
        }
    }

    /// Is the anchor in the same day/week/month/year as today?
    private var isCurrentPeriod: Bool {
        guard let comp = period.calendarComponent else { return true }
        return Calendar.current.isDate(anchor, equalTo: .now, toGranularity: comp)
    }

    /// Move the anchor one period back (-1) or forward (+1).
    private func shift(_ delta: Int) {
        guard let comp = period.calendarComponent else { return }
        anchor = Calendar.current.date(byAdding: comp, value: delta, to: anchor) ?? anchor
    }

    /// The 2×2 grid: Places, Traveled, Cities, Countries.
    private func statGrid(_ s: RecapStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: "\(s.uniquePlaces)", label: "Places", icon: "mappin.and.ellipse")
            StatTile(value: String(format: "%.0f km", s.distanceKm), label: "Traveled", icon: "road.lanes")
            StatTile(value: "\(s.cities.count)", label: "Cities", icon: "building.2")
            StatTile(value: "\(s.countries.count)", label: "Countries", icon: "globe")
        }
    }

    /// A titled, horizontally scrolling row of capsule "chips" (used for cities/countries).
    private func chipSection(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Where you spent your time": rank · name/city · total time/visit count.
    private func topPlaces(_ s: RecapStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Where you spent your time", systemImage: "star.fill").font(.headline)
            ForEach(Array(s.topPlaces.enumerated()), id: \.element.id) { i, place in
                HStack {
                    // Rank number
                    Text("\(i + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 28)
                        .foregroundStyle(.orange)
                    // Name + "City, Country"
                    VStack(alignment: .leading) {
                        Text(place.name).font(.subheadline.bold()).lineLimit(1)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    // Total time + visit count
                    VStack(alignment: .trailing) {
                        Text(place.totalTime.shortDuration).font(.subheadline)
                        Text("\(place.visits) visit\(place.visits == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - StatTile

/// One rounded card in the stat grid: icon, big number, small label.
struct StatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(value).font(.title.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - RecapMap

/// Map with your path and the places you stayed.
///
/// Orange line = breadcrumbs (LocationPoints) in time order.
/// Pins = the top 10 places for the period.
struct RecapMap: View {
    let stats: RecapStats

    var body: some View {
        // `.automatic` zooms the camera to fit everything drawn on the map.
        Map(initialPosition: .automatic) {
            if stats.points.count > 1 {
                MapPolyline(coordinates: stats.points.map(\.coordinate))
                    .stroke(.orange.opacity(0.7), lineWidth: 3)
            }
            ForEach(stats.topPlaces) { place in
                Marker(place.name, systemImage: "mappin", coordinate: place.coordinate)
                    .tint(.orange)
            }
        }
        // Hide Apple's own POI icons so our pins stand out.
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        // `initialPosition` only applies on first appearance; changing the id forces SwiftUI
        // to rebuild the map (and re-fit the camera) whenever you switch period.
        .id(stats.title) // re-fit the camera when the period changes
    }
}

// MARK: - Previews (Xcode canvas only — open with ⌥⌘↩)

#if DEBUG
#Preview("Recap · sample data") {
    RecapView()
        .modelContainer(PreviewData.container)
        .environmentObject(LocationTracker.shared)
}

#Preview("Recap · empty") {
    RecapView()
        .modelContainer(PreviewData.emptyContainer)
        .environmentObject(LocationTracker.shared)
}

#Preview("Recap · dark mode") {
    RecapView()
        .modelContainer(PreviewData.container)
        .environmentObject(LocationTracker.shared)
        .preferredColorScheme(.dark)
}

#Preview("Stat tile") {
    StatTile(value: "42", label: "Places", icon: "mappin.and.ellipse")
        .frame(width: 180)
        .padding()
}

#Preview("Recap map") {
    RecapMap(stats: PreviewData.stats(.week))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding()
        .modelContainer(PreviewData.container)
}
#endif
