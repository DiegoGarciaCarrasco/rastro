import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var tracker: LocationTracker
    @Environment(\.modelContext) private var context
    @Query private var visits: [Visit]
    @Query private var points: [LocationPoint]
    @State private var confirmDelete = false

    // Replace with your hosted privacy policy URL (see PRIVACY_POLICY.md).
    private let privacyURL = URL(string: "https://yourname.github.io/rastro/privacy")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
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

                Section("Your data") {
                    LabeledContent("Visits saved", value: "\(visits.count)")
                    LabeledContent("Path points saved", value: "\(points.count)")
                    Button("Delete all my data", role: .destructive) { confirmDelete = true }
                }

                Section("About") {
                    Link("Privacy Policy", destination: privacyURL)
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all visits and history? This can't be undone.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: deleteAll)
            }
        }
    }

    private var permissionText: String {
        switch tracker.authorizationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not set"
        }
    }

    private func deleteAll() {
        try? context.delete(model: Visit.self)
        try? context.delete(model: LocationPoint.self)
        try? context.save()
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
