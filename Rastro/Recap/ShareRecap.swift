//
//  ShareRecap.swift
//  Rastro
//
//  SHARE CARD — the "Wrapped"-style image you can send to friends / post on Instagram.
//
//   • `ShareRecapButton` — the toolbar button on the Recap tab. Renders the card to an
//                          image and opens the iOS share sheet with it.
//   • `RecapCard`        — the card's design (gradient background, big numbers, top 5).
//
//  To redesign the shared image, edit `RecapCard` only.
//

import SwiftUI

// MARK: - ShareRecapButton

/// Renders a shareable "Wrapped"-style image of the recap.
struct ShareRecapButton: View {
    let stats: RecapStats
    /// Screen pixel density (2× / 3×) so the exported image is sharp, not blurry.
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // NOTE: the image is re-rendered every time this button redraws (i.e. every
        // RecapView redraw). Rendering lazily on tap would be cheaper.
        if let image = render() {
            ShareLink(item: image,
                      preview: SharePreview("My \(stats.title) recap", image: image)) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    /// Draws `RecapCard` off-screen into a bitmap using SwiftUI's `ImageRenderer`.
    @MainActor
    private func render() -> Image? {
        let renderer = ImageRenderer(content: RecapCard(stats: stats))
        renderer.scale = displayScale
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

// MARK: - RecapCard

/// The visual design of the shared image (fixed 380 pt wide, height fits content).
struct RecapCard: View {
    let stats: RecapStats

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Branding + period title
            Text("RASTRO").font(.caption.bold()).kerning(3).opacity(0.8)
            Text(stats.title)
                .font(.system(size: 40, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Headline numbers
            HStack(spacing: 24) {
                big("\(stats.uniquePlaces)", "places")
                big(String(format: "%.0f", stats.distanceKm), "km")
                big("\(stats.cities.count)", "cities")
                big("\(stats.countries.count)", "countries")
            }

            // Top 5 places
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

    /// One big-number + small-label pair, e.g. "42 / places".
    private func big(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold())
            Text(label).font(.caption).opacity(0.85)
        }
    }
}

// MARK: - Previews (Xcode canvas only — open with ⌥⌘↩)

#if DEBUG
/// Shows exactly what the shared image looks like.
#Preview("Share card · month") {
    RecapCard(stats: PreviewData.stats(.month))
        .modelContainer(PreviewData.container)
}

#Preview("Share card · all time") {
    RecapCard(stats: PreviewData.stats(.allTime))
        .modelContainer(PreviewData.container)
}
#endif
