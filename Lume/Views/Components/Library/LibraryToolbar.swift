import SwiftUI

struct LibraryToolbarModifier: ViewModifier {
    @Binding var categorySortRaw: String
    @Binding var contentSortRaw: String
    @Binding var showingSync: Bool
    @Binding var showingRefreshAll: Bool
    @Binding var showingSettings: Bool
    let refreshablePlaylists: [Playlist]

    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SortMenu(categorySortRaw: $categorySortRaw, contentSortRaw: $contentSortRaw)
                }

                // One ToolbarItem each, deliberately not an HStack in a single
                // item: when the bar runs out of room it moves surplus items
                // into a "..." overflow menu, and an item whose content is a
                // stack of buttons has no menu representation — it was dropped
                // outright, leaving no way to reach Settings at all. Separate
                // items degrade into menu rows instead. The titles also give the
                // menu rows (and VoiceOver) real names rather than the symbols'
                // defaults.
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            showingSync = true
                        } label: {
                            Label("Refresh Playlist…", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showingRefreshAll = true
                        } label: {
                            Label("Refresh All Playlists…", systemImage: "arrow.clockwise.circle")
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(refreshablePlaylists.isEmpty)
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(
                isPresented: $showingSettings,
                // Settings is a sheet on this toolbar, invisible to the browse
                // root that raises the rating prompt and the root notices — so
                // it reports itself, the way the paywall and the players do.
                onDismiss: { ScreenOccupancy.shared.noteBlockingSheetDismissed() },
                content: {
                    SettingsView()
                        .onAppear { ScreenOccupancy.shared.noteBlockingSheetAppeared() }
                }
            )
            .sheet(isPresented: $showingSync) {
                PlaylistRefreshView(playlists: refreshablePlaylists)
            }
            .sheet(isPresented: $showingRefreshAll) {
                RefreshAllProgressView(playlists: refreshablePlaylists)
            }
            // A pairing link's add-device sheet is presented from the browse
            // root, which can't present over these.
            .onChange(of: router?.cloudPairingRequest?.id) { _, request in
                guard request != nil else { return }
                showingSettings = false
                showingSync = false
            }
    }
}

struct LibraryToolbarConfiguration {
    @Binding var categorySortRaw: String
    @Binding var contentSortRaw: String
    @Binding var showingSync: Bool
    @Binding var showingRefreshAll: Bool
    @Binding var showingSettings: Bool
    let refreshablePlaylists: [Playlist]
}

extension View {
    func libraryToolbar(config: LibraryToolbarConfiguration) -> some View {
        #if os(tvOS)
            // tvOS surfaces sync/settings/sorting through the tab bar instead.
            return self
        #else
            return modifier(LibraryToolbarModifier(
                categorySortRaw: config.$categorySortRaw,
                contentSortRaw: config.$contentSortRaw,
                showingSync: config.$showingSync,
                showingRefreshAll: config.$showingRefreshAll,
                showingSettings: config.$showingSettings,
                refreshablePlaylists: config.refreshablePlaylists
            ))
        #endif
    }
}
