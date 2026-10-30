import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var tracker: LocationTracker

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
            Text("Rastro")
                .font(.largeTitle.bold())
            Text("Your private travel diary. Rastro quietly remembers the places you visit and turns them into monthly and yearly recaps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 14) {
                Label("Data stays on your iPhone", systemImage: "lock.fill")
                Label("Low battery: no constant GPS", systemImage: "battery.75percent")
                Label("Pause or delete anytime", systemImage: "trash")
            }
            .font(.subheadline)

            Spacer()

            if tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted {
                Text("Location access is off. Turn it on in Settings → Rastro → Location → Always.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    tracker.requestPermission()
                } label: {
                    Text("Start tracking").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
    }
}

/// Small banner shown when the user only gave "While Using" permission.
struct AlwaysPermissionBanner: View {
    @EnvironmentObject private var tracker: LocationTracker

    var body: some View {
        if !tracker.hasAlways {
            VStack(alignment: .leading, spacing: 8) {
                Label("Tracking only while the app is open", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                Text("Allow \"Always\" so Rastro can log places in the background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Allow Always") {
                    if tracker.authorizationStatus == .authorizedWhenInUse {
                        tracker.requestPermission()
                    }
                    // If iOS already showed the prompt once, it won't again — send them to Settings.
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote.bold())
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
