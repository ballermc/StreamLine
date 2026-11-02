//
//  SettingsView+Library.swift
//  Lume
//
//  Library settings aggregate tab visibility across unlocked playlists (plus
//  the app-wide Sports tab) and manage Categories & Channels across those
//  sources (Content Management, PIN-gated).
//
//  iOS / macOS: `LibrarySettingsView`, pushed from the root row. tvOS: the
//  Library pane, whose Categories & Channels row drills in place.
//

import SwiftData
import SwiftUI

extension Playlist {
    /// Whether `tab` shows for this playlist, as a switch. Saved straight away
    /// and handed to iCloud sync, so other devices pick the change up too.
    func tabVisibility(
        _ tab: PlaylistTab,
        context: ModelContext,
        cloudSync: CloudSyncCoordinator?
    ) -> Binding<Bool> {
        Binding(
            get: { !self.hiddenTabs.contains(tab) },
            set: { shows in
                var hidden = self.hiddenTabs
                if shows {
                    hidden.remove(tab)
                } else {
                    hidden.insert(tab)
                }
                self.hiddenTabs = hidden
                try? context.save()
                Task { @MainActor in cloudSync?.reconcile() }
            }
        )
    }
}

extension PlaylistTab {
    var title: LocalizedStringKey {
        switch self {
        case .movies: "Movies"
        case .series: "Series"
        case .liveTV: "Live TV"
        }
    }
}

private extension [Playlist] {
    func tabVisibility(
        _ tab: PlaylistTab,
        context: ModelContext,
        cloudSync: CloudSyncCoordinator?
    ) -> Binding<Bool> {
        let sources = unlocked()
        return Binding(
            get: { sources.contains { !$0.hiddenTabs.contains(tab) } },
            set: { shows in
                for source in sources {
                    var hidden = source.hiddenTabs
                    if shows {
                        hidden.remove(tab)
                    } else {
                        hidden.insert(tab)
                    }
                    source.hiddenTabs = hidden
                }
                try? context.save()
                Task { @MainActor in cloudSync?.reconcile() }
            }
        )
    }
}

#if !os(tvOS)

    struct LibrarySettingsView: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(CloudSyncCoordinator.self) private var cloudSync: CloudSyncCoordinator?
        @Query private var playlists: [Playlist]
        @AppStorage(SportsSyncService.tabEnabledKey) private var sportsTabEnabled = SportsSyncService.tabEnabledDefault

        var body: some View {
            let unlockedPlaylists = playlists.unlocked()
            List {
                Section {
                    if !unlockedPlaylists.isEmpty {
                        ForEach(PlaylistTab.allCases) { tab in
                            Toggle(tab.title, isOn: playlists.tabVisibility(
                                tab, context: modelContext, cloudSync: cloudSync
                            ))
                        }
                    }
                    Toggle("Sports", isOn: $sportsTabEnabled)
                } header: {
                    Text("Tabs")
                } footer: {
                    if !unlockedPlaylists.isEmpty {
                        Text("Movies, Series and Live TV are shown when enabled for an unlocked playlist. Sports applies to every playlist.")
                    }
                }

                Section {
                    NavigationLink {
                        ParentalGateView { ContentManagementView() }
                    } label: {
                        Text("Categories & Channels")
                    }
                    .disabled(unlockedPlaylists.isEmpty)
                } header: {
                    Text("Content")
                } footer: {
                    Text("Hide and reorder categories and channels across your unlocked playlists.")
                }
            }
            .platformNavigationTitle("Library")
        }
    }

#endif

#if os(tvOS)

    extension SettingsView {
        var tvLibraryDetail: some View {
            let unlockedPlaylists = playlists.unlocked()
            return VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Tabs")
                    if !unlockedPlaylists.isEmpty {
                        ForEach(PlaylistTab.allCases) { tab in
                            TVOptionToggleRow(title: tab.title, isOn: playlists.tabVisibility(
                                tab, context: modelContext, cloudSync: cloudSync
                            ))
                        }
                    }
                    TVOptionToggleRow(title: "Sports", isOn: $sportsTabEnabled)
                    if !unlockedPlaylists.isEmpty {
                        Text("Movies, Series and Live TV are shown when enabled for an unlocked playlist. Sports applies to every playlist.")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                            .padding(.top, 6)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Content")
                    Button {
                        beginContentManagementHandoff()
                        showingContentManagement = true
                    } label: {
                        HStack(spacing: 16) {
                            Text("Categories & Channels")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                    .focused($drillInFocus, equals: .contentManagement)
                    .disabled(unlockedPlaylists.isEmpty)
                    Text("Hide and reorder categories and channels across your unlocked playlists.")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                        .padding(.top, 6)
                }

            }
        }
    }

#endif
