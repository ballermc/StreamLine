//
//  QuickSwitchResolverTests.swift
//  LumeTests
//
//  Covers playlist source scoping and profile quick-switch resolution.
//

import Foundation
@testable import Lume
import SwiftData
import Testing

/// Serialized because profile-store tests read and write
/// `ActiveProfileStore.current` in `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct QuickSwitchResolverTests {
    /// Added in the order given, a second apart — the fallback orders by
    /// `addedAt`, and back-to-back `Date()`s could tie.
    private func makePlaylists(_ names: [String], in context: ModelContext) throws -> [Playlist] {
        let playlists = names.map { Playlist(name: $0, serverURL: "http://\($0)", username: "u", password: "p") }
        for (offset, playlist) in playlists.enumerated() {
            playlist.addedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
            context.insert(playlist)
        }
        try context.save()
        return playlists
    }

    private func makeProfiles(_ names: [String], in context: ModelContext) throws -> [UserProfile] {
        let profiles = names.enumerated().map { UserProfile(name: $0.element, sortOrder: $0.offset) }
        for profile in profiles {
            context.insert(profile)
        }
        try context.save()
        return profiles
    }

    // MARK: - owner(ofContentID:)

    @Test func `content resolves to the playlist whose prefix it carries`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)
        let id = "\(playlists[1].id.uuidString)-live-4021"

        #expect(playlists.owner(ofContentID: id)?.id == playlists[1].id)
    }

    @Test func `content from a playlist that is gone owns nothing`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)

        #expect(playlists.owner(ofContentID: "\(UUID().uuidString)-live-4021") == nil)
    }

    @Test func `the owner resolves provider-specific playback credentials`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)
        let id = "\(playlists[1].id.uuidString)-movie-77"

        #expect(playlists.owner(ofContentID: id)?.id == playlists[1].id)
    }

    // MARK: - Free plan

    @Test func `without Pro only the oldest playlist is unlocked`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second", "Third"], in: container.mainContext)
        let shuffled = [playlists[2], playlists[0], playlists[1]]

        #expect(shuffled.unlocked(isPremium: false).map(\.id) == [playlists[0].id])
        #expect(shuffled.filter { shuffled.isLocked($0, isPremium: false) }.map(\.name) == ["Third", "Second"])
        #expect(shuffled.unlocked(isPremium: true).map(\.id) == shuffled.map(\.id))
        #expect(!shuffled.contains { shuffled.isLocked($0, isPremium: true) })
    }

    @Test func `without Pro content is locked by the playlist prefix on its id`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second"], in: container.mainContext)

        #expect(!playlists.isLocked(contentID: "\(playlists[0].id.uuidString)-movie-1", isPremium: false))
        #expect(playlists.isLocked(contentID: "\(playlists[1].id.uuidString)-movie-1", isPremium: false))
        #expect(!playlists.isLocked(contentID: "\(playlists[1].id.uuidString)-movie-1", isPremium: true))
        #expect(!playlists.isLocked(contentID: "\(UUID().uuidString)-movie-1", isPremium: false))
    }

    @Test func `without Pro the only playlist is never locked`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["Only"], in: container.mainContext)

        #expect(!playlists.isLocked(playlists[0], isPremium: false))
        #expect([Playlist]().unlocked(isPremium: false).isEmpty)
    }

    @Test func `the free plan scopes catalog queries to the oldest playlist`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second", "Third"], in: container.mainContext)

        #expect(playlists.contentScopePrefix(isPremium: false) == "\(playlists[0].id.uuidString)-")
        #expect(playlists.contentScopePrefix(isPremium: true).isEmpty)
    }

    @Test func `all playlist sources are unlocked for Pro in their existing order`() throws {
        let container = try makeProfileTestContainer()
        let playlists = try makePlaylists(["First", "Second", "Third"], in: container.mainContext)
        let shuffled = [playlists[2], playlists[0], playlists[1]]

        #expect(shuffled.unlocked(isPremium: true).map(\.id) == shuffled.map(\.id))
        #expect(!shuffled.contains { shuffled.isLocked($0, isPremium: true) })
    }

    // MARK: - Profile rows

    @Test func `profile rows keep the roster order and mark the active profile current`() throws {
        let container = try makeProfileTestContainer()
        let profiles = try makeProfiles(["Me", "Kids", "Guest"], in: container.mainContext)

        let rows = QuickSwitchResolver.profileRows(profiles, activeProfileID: profiles[2].id)

        #expect(rows.map(\.item.name) == ["Me", "Kids", "Guest"])
        #expect(rows.filter(\.isCurrent).map(\.item.name) == ["Guest"])
        #expect(QuickSwitchResolver.currentProfile(in: profiles, activeProfileID: profiles[2].id)?.id == profiles[2].id)
    }

    @Test func `an unknown active profile id makes no row current`() throws {
        let container = try makeProfileTestContainer()
        let profiles = try makeProfiles(["Me", "Kids"], in: container.mainContext)

        let rows = QuickSwitchResolver.profileRows(profiles, activeProfileID: UUID())

        #expect(rows.allSatisfy { !$0.isCurrent })
        #expect(QuickSwitchResolver.currentProfile(in: profiles, activeProfileID: UUID()) == nil)
    }

    @Test func `the current profile follows the active profile store`() throws {
        let container = try makeProfileTestContainer()
        let profiles = try makeProfiles(["Me", "Kids"], in: container.mainContext)

        let saved = ActiveProfileStore.current
        defer { ActiveProfileStore.current = saved }

        ActiveProfileStore.current = profiles[1].id
        let active = ActiveProfileStore.current ?? UserProfile.defaultProfileID

        #expect(QuickSwitchResolver.currentProfile(in: profiles, activeProfileID: active)?.name == "Kids")
    }

    // MARK: - Row identity

    @Test func `row ids are the item ids the focus targets key on`() throws {
        let container = try makeProfileTestContainer()
        let profiles = try makeProfiles(["Me", "Kids"], in: container.mainContext)

        let profileRows = QuickSwitchResolver.profileRows(profiles, activeProfileID: profiles[0].id)

        #expect(profileRows.map(\.id) == profiles.map(\.id))
    }
}
