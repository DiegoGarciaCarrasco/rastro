import SwiftUI
import SwiftData

@main
struct RastroApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Visit.self, LocationPoint.self)
        } catch {
            fatalError("Could not create data store: \(error)")
        }
        // Must be set up at launch: iOS relaunches the app in the background
        // for visits / significant location changes, and we need to catch them.
        LocationTracker.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(LocationTracker.shared)
        }
        .modelContainer(container)
    }
}
