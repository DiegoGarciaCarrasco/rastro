//
//  RastroApp.swift
//  Rastro
//
//  APP ENTRY POINT — the first code that runs when iOS launches Rastro.
//
//  Responsibilities:
//   1. Create the on-device database (SwiftData `ModelContainer`) for `Visit` and `LocationPoint`.
//   2. Hand that database to `LocationTracker` so it can save location events.
//   3. Build the root UI (`RootView`) and inject the shared tracker + database into it.
//
//  Launch modes (important to understand):
//   • Normal launch: the user taps the icon → `init()` runs → `body` shows the UI.
//   • Background relaunch: the app is closed, the user arrives somewhere / moves ~500 m,
//     and iOS silently relaunches Rastro to deliver that event. `init()` still runs, but
//     no window is shown. That is why the tracker is wired up in `init()` and not in a view.
//
//  Read next: Models/Models.swift → Location/LocationTracker.swift → Views/RootView.swift
//

import SwiftUI
import SwiftData

/// `@main` marks this as the program's entry point (replaces the old AppDelegate/main.swift).
@main
struct RastroApp: App {
    /// The SwiftData database. One container for the whole app; every view and the
    /// tracker read/write through it. Stored on disk in the app's private sandbox.
    let container: ModelContainer

    // MARK: - Launch setup

    init() {
        // Open (or create on first launch) the database with our two model types.
        // If this fails the app can't do anything useful, so we crash loudly.
        // NOTE (App Store): if you later change a model's properties, SwiftData migrates
        // simple changes automatically; complex ones need a `VersionedSchema` +
        // `SchemaMigrationPlan`, otherwise this line can crash for existing users.
        do {
            container = try ModelContainer(for: Visit.self, LocationPoint.self)
        } catch {
            fatalError("Could not create data store: \(error)")
        }
        // Must be set up at launch: iOS relaunches the app in the background
        // for visits / significant location changes, and we need to catch them.
        LocationTracker.shared.configure(container: container)
    }

    // MARK: - UI

    var body: some Scene {
        WindowGroup {
            RootView()
                // Makes the tracker available to any view via `@EnvironmentObject`.
                .environmentObject(LocationTracker.shared)
        }
        // Makes the database available to any view via `@Query` / `@Environment(\.modelContext)`.
        .modelContainer(container)
    }
}
