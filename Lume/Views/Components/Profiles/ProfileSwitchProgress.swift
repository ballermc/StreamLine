import SwiftUI

extension View {
    /// Layers the profile-switch progress overlay over the app without animating
    /// the tab hierarchy.
    func profileSwitchProgressOverlay(profile: ProfileManager?) -> some View {
        overlay {
            ZStack {
                if let profile, profile.isSwitching {
                    SwitchProgressOverlay(message: Text(
                        "Switching profile to \(profile.pendingProfileName ?? "")",
                        comment: "Loading message shown while the app switches to another user profile"
                    ))
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: profile?.isSwitching)
        }
    }
}

/// The visual every switch shares.
private struct SwitchProgressOverlay: View {
    let message: Text

    var body: some View {
        ZStack {
            // Dim and capture taps so the half-rendered catalog isn't
            // interacted with mid-switch.
            Color.black.opacity(0.35)

            VStack(spacing: spacing) {
                ProgressView()
                    .controlSize(controlSize)
                    // Explicit white (not accentColor, which resolves to white on
                    // tvOS but reads as untinted elsewhere) over the dim backdrop.
                    .tint(.white)

                message
                    .font(font)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(padding)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    #if os(tvOS)
        private let spacing: CGFloat = 32
        private let padding: CGFloat = 56
        private let controlSize: ControlSize = .extraLarge
        private let font: Font = .title2
    #else
        private let spacing: CGFloat = 20
        private let padding: CGFloat = 32
        private let controlSize: ControlSize = .large
        private let font: Font = .headline
    #endif
}

#Preview("Profile") {
    SwitchProgressOverlay(message: Text(verbatim: "Switching profile to Profile 2"))
}
