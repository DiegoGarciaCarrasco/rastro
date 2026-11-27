//
//  RootView.swift
//  Rastro
//
//  ROOT SCREEN — decides what the user sees first.
//
//   • No location permission yet (or denied) → OnboardingView
//   • Permission granted (While Using or Always) → the 4-tab app:
//       Recap (RecapView) · History (HistoryView) · Map (AllPlacesMapView) · Settings (SettingsView)
//
//  Because `tracker` is an @EnvironmentObject, this view re-evaluates automatically when
//  the permission changes — e.g. the moment the user taps "Allow" the tabs appear.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var tracker: LocationTracker
    /// Foreground / background / inactive state of the app's window.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if tracker.hasAnyPermission {
                // MARK: Main app (tabs)
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
                // MARK: First run / no permission
                OnboardingView()
            }
        }
        .tint(.orange)   // app-wide accent color
        // Each time the user opens the app, name any visits that were saved while offline.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tracker.geocodeMissing() }
        }
    }
}
