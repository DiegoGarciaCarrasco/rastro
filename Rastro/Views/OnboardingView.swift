//
//  OnboardingView.swift
//  Rastro
//
//  PERMISSION SCREENS
//
//   • `OnboardingView`         — full-screen welcome shown until the user grants location
//                                access. Has two states: "Start tracking" (can still ask)
//                                and "Open Settings" (user denied; iOS won't ask again).
//   • `AlwaysPermissionBanner` — small orange banner at the top of the Recap tab while the
//                                user only granted "While Using" (no background logging).
//
//  Permission logic itself lives in Location/LocationTracker.swift → `requestPermission()`.
//  NOTE (App Store review): Apple checks that the wording here and the Info.plist usage
//  strings honestly explain why "Always" location is needed. Keep them accurate.
//

import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @EnvironmentObject private var tracker: LocationTracker

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Logo + pitch
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
            Text("Rastro")
                .font(.largeTitle.bold())
            Text("Your private travel diary. Rastro quietly remembers the places you visit and turns them into monthly and yearly recaps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            // Three selling points (privacy, battery, control)
            VStack(alignment: .leading, spacing: 14) {
                Label("Data stays on your iPhone", systemImage: "lock.fill")
                Label("Low battery: no constant GPS", systemImage: "battery.75percent")
                Label("Pause or delete anytime", systemImage: "trash")
            }
            .font(.subheadline)

            Spacer()

            // Call to action — depends on the current permission state
            if tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted {
                // Denied: the app can't show the system prompt again; only the Settings app can fix it.
                Text("Location access is off. Turn it on in Settings → Rastro → Location → Always.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    // Deep-links straight to Rastro's page in the iOS Settings app.
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Not asked yet: shows the system "Allow While Using" prompt.
                // Once granted, RootView swaps this screen for the tabs automatically.
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

// MARK: - AlwaysPermissionBanner

/// Small banner shown when the user only gave "While Using" permission.
/// Renders nothing once "Always" is granted.
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
                    // Try the in-app "Change to Always Allow" prompt first…
                    if tracker.authorizationStatus == .authorizedWhenInUse {
                        tracker.requestPermission()
                    }
                    // …and also open Settings as a fallback.
                    // NOTE: both happen on the same tap, so the prompt and the Settings app
                    // can compete; consider opening Settings only if the prompt was already used.
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

// MARK: - Previews (Xcode canvas only — open with ⌥⌘↩)

#if DEBUG
#Preview("Onboarding") {
    OnboardingView()
        .environmentObject(LocationTracker.shared)
}

#Preview("Onboarding · dark mode") {
    OnboardingView()
        .environmentObject(LocationTracker.shared)
        .preferredColorScheme(.dark)
}

#Preview("Always-permission banner") {
    AlwaysPermissionBanner()
        .environmentObject(LocationTracker.shared)
        .padding()
}
#endif
