import SwiftUI
import SwiftData
import MapKit

/// Day-by-day list of every place you stayed.
struct HistoryView: View {
    @Query(sort: \Visit.arrival, order: .reverse) private var visits: [Visit]
    @Environment(\.modelContext) private var context

    private var byDay: [(day: Date, visits: [Visit])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: visits) { cal.startOfDay(for: $0.arrival) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(byDay, id: \.day) { group in
                    Section(group.day.formatted(.dateTime.weekday(.wide).month().day().year())) {
                        ForEach(group.visits) { visit in
                            NavigationLink { VisitDetailView(visit: visit) } label: {
                                VisitRow(visit: visit)
                            }
                        }
                        .onDelete { idx in
                            idx.map { group.visits[$0] }.forEach(context.delete)
                            try? context.save()
                        }
                    }
                }
            }
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

struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
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

    private var timeRange: String {
        let start = visit.arrival.formatted(date: .omitted, time: .shortened)
        guard let end = visit.departure else { return "\(start) – now" }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

struct VisitDetailView: View {
    let visit: Visit

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: visit.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                    Marker(visit.displayName, coordinate: visit.coordinate).tint(.orange)
                }
                .frame(height: 220)
                .listRowInsets(EdgeInsets())
            }
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
