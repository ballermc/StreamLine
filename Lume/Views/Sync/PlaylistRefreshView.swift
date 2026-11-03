import SwiftUI

/// Lets the viewer choose one account before starting a manual refresh.
struct PlaylistRefreshView: View {
    let playlists: [Playlist]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlaylistID: UUID?
    @State private var refreshEPG = false
    @State private var showingProgress = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist") {
                    Picker("Account", selection: $selectedPlaylistID) {
                        Text("Choose a playlist").tag(nil as UUID?)
                        ForEach(playlists) { playlist in
                            Text(playlist.name).tag(Optional(playlist.id))
                        }
                    }
                    Toggle("Refresh EPG", isOn: $refreshEPG)
                } footer: {
                    Text("Refreshing the EPG updates guide data for all enabled sources.")
                }
            }
            .navigationTitle("Refresh Playlist")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { showingProgress = true }
                        .disabled(selectedPlaylistID == nil)
                }
            }
        }
        .onAppear {
            if selectedPlaylistID == nil { selectedPlaylistID = playlists.first?.id }
        }
        .sheet(isPresented: $showingProgress, onDismiss: { dismiss() }) {
            if let selectedPlaylistID,
               let selectedPlaylist = playlists.first(where: { $0.id == selectedPlaylistID }) {
                SyncProgressView(playlist: selectedPlaylist, refreshEPG: refreshEPG)
            }
        }
    }
}
