import SwiftUI
import SwiftData
import MapKit

/// Every place you've ever been, on one map.
struct AllPlacesMapView: View {
    @Query private var visits: [Visit]
    @State private var position: MapCameraPosition = .automatic

    /// One pin per distinct place (not per visit).
    private var places: [Visit] {
        var seen = Set<String>()
        return visits.filter { seen.insert($0.placeKey).inserted }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
                ForEach(places) { v in
                    Annotation(v.displayName, coordinate: v.coordinate) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .navigationTitle("\(places.count) places")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
