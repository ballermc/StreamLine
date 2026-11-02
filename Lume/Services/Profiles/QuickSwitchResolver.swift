//
//  QuickSwitchResolver.swift
//  Lume
//
//  The shared answer for profile quick-switch surfaces.
//
//  Deliberately platform-agnostic and view-free: the test targets exclude
//  appletvos, so nothing here may be gated behind `#if os(tvOS)`.
//

import Foundation

// MARK: - Rows

/// One row on a switch surface and whether it is currently selected.
struct QuickSwitchRow<Item>: Identifiable {
    let item: Item
    let isCurrent: Bool
    let id: UUID
}

// MARK: - Playlist scope

extension [Playlist] {
    /// The catalog ID prefix shared by every playlist available to the current
    /// plan. The free plan has one unlocked playlist; Pro includes all sources.
    func contentScopePrefix(isPremium: Bool? = nil) -> String {
        guard !PremiumManager.isPremium(isPremium) else { return "" }
        return oldest.map { "\($0.id.uuidString)-" } ?? ""
    }

    /// The playlist added first — the free plan's one unlocked playlist.
    var oldest: Playlist? {
        self.min { ($0.addedAt, $0.id.uuidString) < ($1.addedAt, $1.id.uuidString) }
    }

    /// Whether the plan puts `playlist` out of reach. The free plan includes one
    /// playlist, the oldest; the rest still arrive — iCloud and Lume Cloud bring
    /// over every playlist added on a device with Pro, or in Lume for Android —
    /// and stay listed in Settings so they can be deleted or unlocked, but are
    /// not synced, searched, or played.
    ///
    /// `isPremium` pins the plan (tests); nil reads `PremiumManager`. The same
    /// goes for every plan-aware helper here.
    func isLocked(_ playlist: Playlist, isPremium: Bool? = nil) -> Bool {
        !PremiumManager.isPremium(isPremium) && playlist.id != oldest?.id
    }

    /// Whether a catalog row came from a playlist the plan locks, by the
    /// playlist prefix on its id. An id no playlist owns isn't locked.
    func isLocked(contentID: String, isPremium: Bool? = nil) -> Bool {
        owner(ofContentID: contentID).map { isLocked($0, isPremium: isPremium) } ?? false
    }

    /// The playlists the plan can use: all of them with Pro, else the oldest.
    func unlocked(isPremium: Bool? = nil) -> [Playlist] {
        PremiumManager.isPremium(isPremium) ? self : (oldest.map { [$0] } ?? [])
    }

    /// The playlist that synced a piece of content. Every catalog id is
    /// prefixed with its playlist's UUID (see `ContentSyncManager`), and that
    /// prefix is the only thing tying a row back to the server and credentials
    /// that can actually play it. Returns `nil` for an id no current playlist
    /// owns, so callers pick their own fallback.
    func owner(ofContentID contentID: String) -> Playlist? {
        first { contentID.hasPrefix($0.id.uuidString) }
    }
}

// MARK: - Plan

extension PremiumManager {
    /// `override` when given, else the live plan. The plan-aware playlist
    /// helpers take an optional rather than defaulting to `shared.isPremium`:
    /// a default argument is evaluated outside the main actor.
    static func isPremium(_ override: Bool?) -> Bool {
        override ?? shared.isPremium
    }
}

// MARK: - Resolver

enum QuickSwitchResolver {
    // MARK: Profiles

    /// The active profile out of `profiles` (always `ProfileManager.profiles` —
    /// `UserProfile` lives in the CloudKit-mirrored container, which the view
    /// contexts don't bind to, so it can never come from a `@Query`).
    static func currentProfile(in profiles: [UserProfile], activeProfileID: UUID) -> UserProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// The profile rows in roster order, each tagged with whether it is active.
    static func profileRows(_ profiles: [UserProfile], activeProfileID: UUID) -> [QuickSwitchRow<UserProfile>] {
        rows(profiles, id: \.id, currentID: activeProfileID)
    }

    // MARK: Shared

    private static func rows<Item>(
        _ items: [Item],
        id: (Item) -> UUID,
        currentID: UUID?
    ) -> [QuickSwitchRow<Item>] {
        items.map { item in
            let itemID = id(item)
            return QuickSwitchRow(item: item, isCurrent: itemID == currentID, id: itemID)
        }
    }
}
