//
//  SettingsView+Playlists.swift
//  Lume
//
//  The Playlists settings page: the playlist list with its sync state, Add
//  Playlist, and the shared Automatic Sync interval.
//
//  iOS / macOS: `PlaylistsSettingsView`, pushed from the root row.
//
//  tvOS: the Playlists pane — the management surface: add, edit, delete, and
//  refresh playlists. All unlocked sources are active simultaneously.
//

import SwiftData
import SwiftUI

private extension [Playlist] {
    /// The free plan's note under the playlist list. Once playlists beyond the
    /// free one have arrived — from iCloud, Lume Cloud or Lume for Android — the
    /// news is that they're locked, not that no more can be added.
    var freePlanFooter: Text {
        count > 1
            ? Text("Free includes one playlist, the first one added. Upgrade to Lume Pro to use the others.")
            : Text("Free includes one playlist. Upgrade to Lume Pro to add more.")
    }
}

#if !os(tvOS)

    struct PlaylistsSettingsView: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(CloudSyncCoordinator.self) private var cloudSync: CloudSyncCoordinator?
        @Query private var playlists: [Playlist]
        @AppStorage(SyncFrequency.storageKey) private var syncFrequencyRaw: String = SyncFrequency.defaultValue.rawValue
        @State private var premium = PremiumManager.shared
        @State private var showingAddPlaylist = false
        @State private var showPaywall = false

        /// Whether a new playlist can be added for free (first playlist always free).
        private var canAddPlaylist: Bool {
            premium.isPremium || playlists.isEmpty
        }

        private var syncFrequency: Binding<SyncFrequency> {
            Binding(
                get: { SyncFrequency.resolve(syncFrequencyRaw) },
                set: { syncFrequencyRaw = $0.rawValue }
            )
        }

        var body: some View {
            List {
                playlistsSection
                autoSyncSection
            }
            .platformNavigationTitle("Playlists")
            .paywall(isPresented: $showPaywall, highlight: .multiplePlaylists)
            .sheet(isPresented: $showingAddPlaylist) {
                LoginView(isModal: true)
            }
        }

        private var playlistsSection: some View {
            Section {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(playlist.name)
                                Text(playlist.displayURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 0)
                            if playlists.isLocked(playlist) {
                                PremiumBadge()
                            } else {
                                PlaylistSyncAccessory(state: playlist.syncState())
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
                .onDelete(perform: deletePlaylists)

                Button {
                    if canAddPlaylist {
                        showingAddPlaylist = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Add Playlist", systemImage: canAddPlaylist ? "plus" : "crown")
                }
            } footer: {
                if playlists.isEmpty {
                    EmptyView()
                } else if premium.isPremium {
                    Text("\(playlists.count) playlist\(playlists.count == 1 ? "" : "s")")
                } else {
                    playlists.freePlanFooter
                }
            }
        }

        private var autoSyncSection: some View {
            Section {
                Picker("Refresh", selection: syncFrequency) {
                    ForEach(SyncFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                .pickerStyle(.menu)
                .disabled(playlists.isEmpty)
            } header: {
                Text("Automatic Sync")
            } footer: {
                Text("Playlists refresh automatically in the background at this interval. Disable a specific playlist's sync in its details. The TV guide refreshes on its own schedule.")
            }
        }

        private func deletePlaylists(offsets: IndexSet) {
            // Route through the sync engine so the deletion also clears the
            // CloudKit mirror and shadow baseline — deleting on the view
            // context alone leaves a surviving mirror that resurrects the last
            // playlist (#136). Previews have no coordinator; local-only
            // deletion is fine there.
            if let cloudSync {
                let ids = offsets.map { playlists[$0].id }
                Task {
                    for id in ids {
                        await cloudSync.deletePlaylist(id: id)
                    }
                }
            } else {
                withAnimation {
                    for index in offsets {
                        PlaylistDeletion.delete(playlists[index], in: modelContext)
                    }
                }
            }
        }
    }

#endif

#if os(tvOS)

    extension SettingsView {
        var tvPlaylistsDetail: some View {
            VStack(alignment: .leading, spacing: 36) {
                tvPlaylistsList
                tvAutoSyncSection
            }
        }

        private var tvPlaylistsList: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("Playlists")

                if playlists.isEmpty {
                    Text("No playlists yet. Add your IPTV provider to start streaming.")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(playlists) { playlist in
                        tvPlaylistRow(playlist)
                    }
                }

                Button {
                    if canAddPlaylist {
                        showingAddPlaylist = true
                    } else {
                        presentPaywall(.multiplePlaylists)
                    }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: canAddPlaylist ? "plus" : "crown")
                            .font(.system(size: 22, weight: .medium))
                        Text("Add Playlist")
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(TVSettingsRowButtonStyle())

                if !premium.isPremium {
                    playlists.freePlanFooter
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                        .padding(.top, 6)
                }
            }
        }

        /// A full-width settings row for source details. Tapping edits this
        /// provider; it does not change which catalogs are visible.
        private func tvPlaylistRow(_ playlist: Playlist) -> some View {
            Button {
                selectedPlaylist = playlist
            } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                        Text(playlist.displayURL)
                            .font(.system(size: TVSettingsMetrics.secondaryFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if playlists.isLocked(playlist) {
                        PremiumBadge()
                    } else {
                        PlaylistSyncAccessory(state: playlist.syncState(), size: 26)
                    }
                    Image(systemName: "pencil")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(TVSettingsRowButtonStyle())
            .focused($drillInFocus, equals: .playlist(playlist.id))
            .accessibilityLabel("Edit \(playlist.name)")
        }
    }

#endif
