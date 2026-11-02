//
//  EPGSyncService.swift
//  Lume
//
//  Owns the background EPG refresh task and publishes whether one is running,
//  for the EPG settings screen. Singleton because it must outlive any one view
//  and be reachable from launch, content-sync completion hooks, and manual
//  refresh actions.
//

import Foundation
import Observation
import OSLog
import SwiftData

/// When a background guide refresh may run, given the playlist content syncs
/// around it. Pure so the ordering can be unit-tested; `EPGSyncService` owns
/// the one instance and feeds it.
///
/// Both downloads hit the same provider account, and Xtream panels commonly
/// cap an account at one concurrent connection — a guide download racing the
/// catalog sync gets one of the two rejected (and can leave the account
/// briefly blocked, failing the sync's next requests too). So the gate is fed
/// the real state from the places that own it, rather than predicting which
/// sync is about to start: `MainTabView` reports whether its auto-sync queue
/// holds anything, `SyncProgressView` reports individual manual syncs, and
/// `RefreshAllProgressView` holds a batch gate through its catalog and guide
/// refreshes.
struct EPGRefreshGate {
    /// Content syncs running right now, automatic or manual.
    private(set) var runningContentSyncs = 0
    /// Whether auto-syncs are queued or on screen in the blocking cover.
    var isAutoSyncQueued = false
    /// A background refresh that was held back or cut short, run as soon as no
    /// content sync is pending. Set by any deferred trigger and by every
    /// successful sync — a freshly synced playlist's channels shouldn't wait
    /// for the next scheduled run.
    private(set) var isRefreshOwed = false

    var isContentSyncPending: Bool {
        runningContentSyncs > 0 || isAutoSyncQueued
    }

    /// A background trigger asking to refresh. Returns whether it may start
    /// now; otherwise the refresh is owed.
    mutating func request() -> Bool {
        isRefreshOwed = isContentSyncPending
        return !isRefreshOwed
    }

    /// A refresh was cut short and has to run again.
    mutating func owe() {
        isRefreshOwed = true
    }

    mutating func contentSyncStarted() {
        runningContentSyncs += 1
    }

    /// Every start is paired with one finish, whether the sync succeeded,
    /// failed or was aborted. Only success owes a refresh of its own; a failed
    /// or aborted one still releases anything held back while it ran.
    mutating func contentSyncFinished(succeeded: Bool) {
        runningContentSyncs = max(0, runningContentSyncs - 1)
        if succeeded { isRefreshOwed = true }
    }

    /// Whether an owed refresh may start now. Clears the debt when it does.
    mutating func takeOwedRefresh() -> Bool {
        guard isRefreshOwed, !isContentSyncPending else { return false }
        isRefreshOwed = false
        return true
    }

    mutating func clearRefreshOwed() {
        isRefreshOwed = false
    }
}

@Observable
final class EPGSyncService {
    static let shared = EPGSyncService()

    private(set) var isSyncing = false
    private(set) var lastSyncSucceeded = false

    private var container: ModelContainer?
    private var task: Task<Void, Never>?
    /// Whether `task` is a background refresh, which a starting content sync
    /// cancels — rather than a manual "Sync Now", which the viewer asked for.
    @ObservationIgnored private var isBackgroundRefresh = false
    @ObservationIgnored private var gate = EPGRefreshGate()

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
    }

    /// Manual trigger (settings "Sync Now"): refreshes now regardless of the
    /// schedule or any in-flight content sync.
    func syncNow() {
        kick()
    }

    /// Starts a manual guide refresh and waits for the result. Any background
    /// refresh already in flight is cancelled first; a queued refresh is held
    /// by the caller's content-sync batch until this one completes.
    func syncNowAndWait() async -> Bool {
        if let current = task {
            if isBackgroundRefresh {
                current.cancel()
            }
            await current.value
        }
        guard !Task.isCancelled else { return false }
        kick()
        guard let current = task else { return false }
        await current.value
        return lastSyncSucceeded
    }

    /// Background trigger (launch): refreshes only if the guide is stale per
    /// the EPG frequency setting — and never alongside a pending playlist sync
    /// (see `EPGRefreshGate`). A deferred refresh runs once the sync is done.
    func syncIfDue() {
        guard isDue, gate.request() else { return }
        kick(background: true)
    }

    // MARK: - Content sync reports

    /// `MainTabView`'s auto-sync queue went from empty to busy or back.
    func setAutoSyncQueued(_ queued: Bool) {
        gate.isAutoSyncQueued = queued
        runOwedRefresh()
    }

    /// A playlist content sync is starting. A background refresh already in
    /// flight is cancelled and owed rather than left to race it — the guide may
    /// have started first (at launch, or before the viewer switched to a stale
    /// playlist), and the gate alone only keeps it from starting second.
    func contentSyncDidStart() {
        gate.contentSyncStarted()
        if let task, isBackgroundRefresh {
            task.cancel()
            gate.owe()
        }
    }

    /// The content sync reported by `contentSyncDidStart` ended, however it
    /// ended.
    func contentSyncDidFinish(succeeded: Bool) {
        gate.contentSyncFinished(succeeded: succeeded)
        runOwedRefresh()
    }

    /// Ends a coordinated refresh-all operation after its manual EPG pass. The
    /// pass has already paid any refresh debt raised while playlist syncs ran.
    func contentSyncBatchDidFinish() {
        gate.contentSyncFinished(succeeded: false)
        gate.clearRefreshOwed()
        runOwedRefresh()
    }

    private func runOwedRefresh() {
        // `container` first: taking the debt before `configure` would drop it.
        guard container != nil, task == nil, gate.takeOwedRefresh() else { return }
        kick(background: true)
    }

    private var isDue: Bool {
        // A guide-schema bump (new XMLTV signals to capture) forces one refresh
        // regardless of the frequency, so existing users back-fill the new
        // columns on their next launch.
        if EPGSyncSchedule.schemaVersion < SyncFrequency.epgCurrentSchemaVersion { return true }
        let raw = UserDefaults.standard.string(forKey: SyncFrequency.epgStorageKey) ?? ""
        let frequency = SyncFrequency.resolveEPG(raw)
        return frequency.isDue(lastSyncDate: EPGSyncSchedule.lastSyncDate)
    }

    private func kick(background: Bool = false) {
        guard let container, task == nil else { return }
        isSyncing = true
        lastSyncSucceeded = false
        isBackgroundRefresh = background
        let manager = EPGSyncManager(modelContainer: container)
        let playlists = (try? ModelContext(container).fetch(FetchDescriptor<Playlist>())) ?? []
        let lockedPlaylistIDs = Set(playlists.filter { playlists.isLocked($0) }.map(\.id))
        // Background guide refresh: run below the UI so an in-flight sync (which
        // saves into the shared catalog container, churning browse `@Query`s)
        // yields CPU to the main thread instead of competing with it. The
        // profile showed EPG ingest pegging a background thread at 100% in
        // lockstep with a frozen main thread right after a playlist sync.
        task = Task(priority: .utility) {
            let succeeded = await BackgroundActivity.perform("Guide refresh") {
                await manager.syncAllSources(lockedPlaylistIDs: lockedPlaylistIDs)
            }
            if succeeded {
                EPGSyncSchedule.lastSyncDate = Date()
                EPGSyncSchedule.schemaVersion = SyncFrequency.epgCurrentSchemaVersion
            }
            lastSyncSucceeded = succeeded
            isSyncing = false
            task = nil
            Logger.database.info("EPG refresh finished (success: \(succeeded))")
            // A refresh cancelled for a content sync may wind down after that
            // sync already finished and found this task still set.
            runOwedRefresh()
        }
    }
}
