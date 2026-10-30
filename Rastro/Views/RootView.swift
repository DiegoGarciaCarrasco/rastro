import SwiftUI

struct RootView: View {
    @EnvironmentObject private var tracker: LocationTracker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if tracker.hasAnyPermission {
                TabView {
                    RecapView()
                        .tabItem { Label("Recap", systemImage: "sparkles") }
                    HistoryView()
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    AllPlacesMapView()
                        .tabItem { Label("Map", systemImage: "map") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            } else {
                OnboardingView()
            }
        }
        .tint(.orange)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tracker.geocodeMissing() }
        }
    }
}
