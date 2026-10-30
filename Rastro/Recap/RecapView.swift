import SwiftUI
import SwiftData
import MapKit

struct RecapView: View {
    @Query(sort: \Visit.arrival) private var visits: [Visit]
    @Query(sort: \LocationPoint.timestamp) private var points: [LocationPoint]

    @State private var period: RecapPeriod = .month
    @State private var anchor: Date = .now

    private var stats: RecapStats {
        RecapStats.make(period: period, anchor: anchor, allVisits: visits, allPoints: points)
    }

    var body: some View {
        let stats = self.stats
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AlwaysPermissionBanner()

                    Picker("Period", selection: $period) {
                        ForEach(RecapPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // Jump back to the current day/week/month/year when switching tabs
                    .onChange(of: period) { _, _ in anchor = .now }

                    periodStepper(title: stats.title)

                    if stats.visits.isEmpty && stats.points.isEmpty {
                        ContentUnavailableView("Nothing yet",
                            systemImage: "figure.walk",
                            description: Text("Go places! Rastro records visits automatically. Check back in a day or two."))
                            .padding(.top, 40)
                    } else {
                        RecapMap(stats: stats)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        statGrid(stats)

                        if !stats.countries.isEmpty {
                            chipSection(title: "Countries", items: stats.countries, icon: "globe.americas.fill")
                        }
                        if !stats.cities.isEmpty {
                            chipSection(title: "Cities", items: stats.cities, icon: "building.2.fill")
                        }

                        topPlaces(stats)
                    }
                }
                .padding()
            }
            .navigationTitle("Recap")
            .toolbar {
                if !stats.visits.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareRecapButton(stats: stats)
                    }
                }
            }
        }
    }

    // MARK: Pieces

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

    private var isCurrentPeriod: Bool {
        guard let comp = period.calendarComponent else { return true }
        return Calendar.current.isDate(anchor, equalTo: .now, toGranularity: comp)
    }

    private func shift(_ delta: Int) {
        guard let comp = period.calendarComponent else { return }
        anchor = Calendar.current.date(byAdding: comp, value: delta, to: anchor) ?? anchor
    }

    private func statGrid(_ s: RecapStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: "\(s.uniquePlaces)", label: "Places", icon: "mappin.and.ellipse")
            StatTile(value: String(format: "%.0f km", s.distanceKm), label: "Traveled", icon: "road.lanes")
            StatTile(value: "\(s.cities.count)", label: "Cities", icon: "building.2")
            StatTile(value: "\(s.countries.count)", label: "Countries", icon: "globe")
        }
    }

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

    private func topPlaces(_ s: RecapStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Where you spent your time", systemImage: "star.fill").font(.headline)
            ForEach(Array(s.topPlaces.enumerated()), id: \.element.id) { i, place in
                HStack {
                    Text("\(i + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 28)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(place.name).font(.subheadline.bold()).lineLimit(1)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
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

/// Map with your path and the places you stayed.
struct RecapMap: View {
    let stats: RecapStats

    var body: some View {
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
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .id(stats.title) // re-fit the camera when the period changes
    }
}
