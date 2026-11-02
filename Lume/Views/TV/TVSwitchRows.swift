//
//  TVSwitchRows.swift
//  Lume
//
//  The profile row shared by the tvOS Settings pane and quick-switch overlay.
//

#if os(tvOS)

    import SwiftUI

    /// A full-width profile row: avatar and name, with a checkmark on the active
    /// one.
    struct TVProfileSwitchRow: View {
        let profile: UserProfile
        let isActive: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 16) {
                    ProfileAvatarView(profile: profile, size: 44)
                    Text(profile.name)
                    Spacer(minLength: 0)
                    if isActive {
                        TVSwitchRowCheckmark()
                    }
                }
            }
            .buttonStyle(TVSettingsRowButtonStyle())
            .modifier(TVSwitchRowActiveState(isActive: isActive))
        }
    }

    /// Announces the active row as selected. The checkmark alone is invisible to
    /// VoiceOver as state — it reads as another glyph in the label — so it is
    /// hidden and the state is carried by the value and the trait instead.
    struct TVSwitchRowActiveState: ViewModifier {
        let isActive: Bool

        func body(content: Content) -> some View {
            if isActive {
                content
                    .accessibilityValue(
                        Text(
                            "Active",
                            comment: "Accessibility value on the playlist or profile row that is currently in use"
                        )
                    )
                    .accessibilityAddTraits(.isSelected)
            } else {
                content
            }
        }
    }

    /// The active marker. Follows the row's focus treatment the way
    /// `TVSettingsRowButtonStyle` does — a white glyph would vanish into the
    /// focused row's near-white fill. Always explicit, never `.accentColor`:
    /// that resolves to white on tvOS.
    struct TVSwitchRowCheckmark: View {
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isFocused ? .black : .white)
                .accessibilityHidden(true)
        }
    }

#endif
