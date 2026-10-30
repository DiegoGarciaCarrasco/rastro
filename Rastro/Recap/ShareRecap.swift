import SwiftUI

/// Renders a shareable "Wrapped"-style image of the recap.
struct ShareRecapButton: View {
    let stats: RecapStats
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = render() {
            ShareLink(item: image,
                      preview: SharePreview("My \(stats.title) recap", image: image)) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    @MainActor
    private func render() -> Image? {
        let renderer = ImageRenderer(content: RecapCard(stats: stats))
        renderer.scale = displayScale
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

struct RecapCard: View {
    let stats: RecapStats

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("RASTRO").font(.caption.bold()).kerning(3).opacity(0.8)
            Text(stats.title).font(.system(size: 40, weight: .heavy))

            HStack(spacing: 24) {
                big("\(stats.uniquePlaces)", "places")
                big(String(format: "%.0f", stats.distanceKm), "km")
                big("\(stats.cities.count)", "cities")
                big("\(stats.countries.count)", "countries")
            }

            if !stats.topPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top places").font(.headline).opacity(0.85)
                    ForEach(Array(stats.topPlaces.prefix(5).enumerated()), id: \.offset) { i, p in
                        Text("\(i + 1). \(p.name)").font(.body.weight(.semibold)).lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: 380, alignment: .leading)
        .background(
            LinearGradient(colors: [.orange, .pink, .purple],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold())
            Text(label).font(.caption).opacity(0.85)
        }
    }
}
