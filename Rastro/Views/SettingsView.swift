//
//  SettingsView.swift
//  Rastro
//
//  SETTINGS TAB — user control over tracking and their data.
//
//  Sections:
//   • Tracking  — on/off toggle (LocationTracker.isTrackingEnabled), current permission,
//                 shortcut to the iOS Settings app.
//   • Your data — how many visits / points are stored, and "Delete all my data".
//   • About     — privacy policy link and app version.
//
//  App Store relevance: an in-app way to pause tracking and delete all data, plus a
//  working privacy policy link, are things Apple reviewers look for in location apps.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var tracker: LocationTracker
    @Environment(\.modelContext) private var context   // for delete-all
    // Loaded only to show the counts. NOTE: this loads every row just to count them;
    // `context.fetchCount(...)` would be lighter once there's lots of data.
    @Query private var visits: [Visit]
    @Query private var points: [LocationPoint]
    @State private var confirmDelete = false            // shows the confirmation dialog

    // ⚠️ MUST CHANGE BEFORE SUBMITTING: still a placeholder URL.
    // Replace with your hosted privacy policy URL (see PRIVACY_POLICY.md).
    private let privacyURL = URL(string: "https://yourname.github.io/rastro/privacy")!

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Tracking
                Section {
                    // Two-way binding straight into the tracker; its `didSet` starts/stops iOS monitoring.
                    Toggle("Record my places", isOn: $tracker.isTrackingEnabled)
                    LabeledContent("Permission", value: permissionText)
                    Button("Open iOS Location Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Tracking")
                } footer: {
                    Text("For full history choose Location → Always and keep Precise Location on.")
                }

                // MARK: Your data
                Section("Your data") {
                    LabeledContent("Visits saved", value: "\(visits.count)")
                    LabeledContent("Path points saved", value: "\(points.count)")
                    Button("Delete all my data", role: .destructive) { confirmDelete = true }
                }

                // MARK: About
                Section("About") {
                    Link("Privacy Policy", destination: privacyURL)
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            // "Are you sure?" sheet before wiping everything.
            .confirmationDialog("Delete all visits and history? This can't be undone.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: deleteAll)
            }
        }
    }

    // MARK: Helpers

    /// Human-readable version of the iOS permission status.
    private var permissionText: String {
        switch tracker.authorizationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not set"
        }
    }

    /// Wipes both tables in one go (batch delete). Tracking keeps running afterwards.
    private func deleteAll() {
        try? context.delete(model: Visit.self)
        try? context.delete(model: LocationPoint.self)
        try? context.save()
    }
}

// MARK: - Bundle helper

extension Bundle {
    /// "1.0 (1)" — marketing version (CFBundleShortVersionString) + build number
    /// (CFBundleVersion). Both come from project.yml: MARKETING_VERSION / CURRENT_PROJECT_VERSION.
    /// Bump the build number for every App Store Connect upload.
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Previews (Xcode canvas only — open with ⌥⌘↩)

#if DEBUG
#Preview("Settings") {
    SettingsView()
        .modelContainer(PreviewData.container)
        .environmentObject(LocationTracker.shared)
}
#endif
