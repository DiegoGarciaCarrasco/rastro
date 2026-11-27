//
//  AllPlacesMapView.swift
//  Rastro
//
//  MAP TAB — every distinct place you've ever been, as orange dots on one big map.
//
//  Unlike the Recap map, there's no period filter and no path line: one dot per
//  `placeKey` (so ten visits to your office = one dot), plus your current location.
//

import SwiftUI
import SwiftData
import MapKit

/// Every place you've ever been, on one map.
struct AllPlacesMapView: View {
    /// All visits (unsorted). Auto-refreshes on new visits.
    @Query private var visits: [Visit]
    /// Camera state. `.automatic` = fit all annotations; bound to the map so the
    /// "my location" button can move it.
    @State private var position: MapCameraPosition = .automatic

    /// One pin per distinct place (not per visit).
    /// `seen.insert(...).inserted` is false for a placeKey we've already kept → filtered out.
    private var places: [Visit] {
        var seen = Set<String>()
        return visits.filter { seen.insert($0.placeKey).inserted }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()   // the blue "you are here" dot
                ForEach(places) { v in
                    // Custom small orange dot with a white border (lighter than a full Marker).
                    Annotation(v.displayName, coordinate: v.coordinate) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            // Standard map buttons: jump to my location, compass.
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .navigationTitle("\(places.count) places")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Previews (Xcode canvas only — open with ⌥⌘↩)

#if DEBUG
#Preview("All places map") {
    AllPlacesMapView()
        .modelContainer(PreviewData.container)
}
#endif
