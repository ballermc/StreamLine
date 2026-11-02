import SwiftData
import SwiftUI

struct RefreshAllProgressView: View {
    let playlists: [Playlist]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .ready
    @State private var playlistResults: [UUID: PlaylistResult] = [:]
    @State private var progress = SyncProgress()
    @State private var activePlaylistName: String?
    @State private var guideState: GuideState = .pending
    @State private var refreshTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case ready
        case refreshing
        case finished
        case cancelled
    }

    private enum PlaylistResult {
        case syncing
        case complete
        case skipped
        case failed(String)
    }

    private enum GuideState: Equatable {
        case pending
        case syncing
        case complete
        case unavailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Playlists")
                            .font(.headline)

                        ForEach(playlists) { playlist in
                            playlistRow(playlist)
                        }

                        if let activePlaylistName {
                            activeProgress
                                .accessibilityLabel("Refreshing \(activePlaylistName)")
                        }

                        Divider()

                        guideRow
                    }
                    .padding()
                }

                Divider()

                footer
                    .padding()
            }
            .navigationTitle("Refresh All")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(phase == .refreshing ? "Cancel" : "Done") {
                            if phase == .refreshing {
                                cancelRefresh()
                            } else {
                                dismiss()
                            }
                        }
                        .disabled(guideState == .syncing)
                    }
                }
        }
        .interactiveDismissDisabled(phase == .refreshing)
        .task {
            let task = Task { await refreshAll() }
            refreshTask = task
            await task.value
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            resultIcon(for: playlist)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body)
                Text(resultDescription(for: playlist))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var activeProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(activePlaylistName ?? "")
                .font(.subheadline.weight(.semibold))
            if let currentStep = progress.currentStep {
                HStack {
                    Image(systemName: currentStep.systemImage)
                        .frame(width: 22)
                    Text(currentStep.title)
                    Spacer()
                    if progress.stepFraction > 0 {
                        Text(progress.stepFraction, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            if !progress.stepDetail.isEmpty {
                Text(progress.stepDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 32)
    }

    private var guideRow: some View {
        HStack(spacing: 12) {
            switch guideState {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .syncing:
                ProgressView()
                    .controlSize(.small)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("TV Guide")
                Text(guideDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var guideDescription: String {
        switch guideState {
        case .pending: "Starts after every playlist finishes"
        case .syncing: "Refreshing enabled guide sources"
        case .complete: "Guide refresh complete"
        case .unavailable: "No guide source could be refreshed"
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .ready, .refreshing:
            if phase == .refreshing {
                ProgressView("Refreshing playlists first, then the TV guide")
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView("Starting refresh")
                    .frame(maxWidth: .infinity)
            }
        case .finished:
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        case .cancelled:
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func resultIcon(for playlist: Playlist) -> some View {
        switch playlistResults[playlist.id] {
        case .some(.syncing):
            ProgressView().controlSize(.small)
        case .some(.complete):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .some(.skipped):
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .some(.failed):
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .none:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    private func resultDescription(for playlist: Playlist) -> String {
        switch playlistResults[playlist.id] {
        case .some(.syncing):
            "Refreshing"
        case .some(.complete):
            "Up to date"
        case .some(.skipped):
            "Already syncing"
        case let .some(.failed(message)):
            message
        case .none:
            "Waiting"
        }
    }

    private func refreshAll() async {
        guard phase == .ready else { return }
        phase = .refreshing
        let epgSync = EPGSyncService.shared
        epgSync.contentSyncDidStart()
        var anyPlaylistSucceeded = false
        var guideRefreshAttempted = false
        defer {
            if guideRefreshAttempted {
                epgSync.contentSyncBatchDidFinish()
            } else {
                epgSync.contentSyncDidFinish(succeeded: anyPlaylistSucceeded)
            }
        }

        let manager = ContentSyncManager(modelContainer: modelContext.container)
        for playlist in playlists {
            guard !Task.isCancelled else {
                phase = .cancelled
                return
            }

            guard playlist.syncStatus != .syncing else {
                playlistResults[playlist.id] = .skipped
                continue
            }

            activePlaylistName = playlist.name
            playlistResults[playlist.id] = .syncing
            let tracker = SyncProgress(steps: SyncStep.steps(for: playlist.sourceType))
            progress = tracker
            do {
                try await BackgroundActivity.perform("Playlist sync") {
                    try await manager.syncPlaylist(playlist, progress: tracker)
                }
                anyPlaylistSucceeded = true
                playlistResults[playlist.id] = .complete
            } catch {
                if Task.isCancelled {
                    playlistResults[playlist.id] = .failed("Cancelled")
                    phase = .cancelled
                    return
                }
                playlistResults[playlist.id] = .failed(error.localizedDescription)
            }
        }

        if anyPlaylistSucceeded {
            ContentIndexingService.shared.kick(after: .seconds(3))
        }

        guard !Task.isCancelled else {
            phase = .cancelled
            return
        }

        activePlaylistName = nil
        guideState = .syncing
        guideRefreshAttempted = true
        guideState = await epgSync.syncNowAndWait() ? .complete : .unavailable
        phase = Task.isCancelled ? .cancelled : .finished
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        dismiss()
    }
}
