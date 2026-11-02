import Foundation
@testable import Lume
import SwiftData
import Testing

@MainActor
struct LiveTVCategoryGroupingTests {
    @Test func `groups live categories by provider and excludes sources without live TV`() throws {
        let schema = Schema([Playlist.self, Lume.Category.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let first = Playlist(name: "First Provider", m3uURL: "https://example.com/first.m3u")
        first.addedAt = Date(timeIntervalSince1970: 1)
        let second = Playlist(name: "Second Provider", m3uURL: "https://example.com/second.m3u")
        second.addedAt = Date(timeIntervalSince1970: 2)
        let fileShare = Playlist(name: "File Share", webdavURL: "https://example.com/dav")
        fileShare.addedAt = Date(timeIntervalSince1970: 3)
        for playlist in [first, second, fileShare] {
            context.insert(playlist)
        }

        let firstCategory = Lume.Category(apiId: "1", name: "News", parentId: 0, type: .live, playlist: first)
        firstCategory.sortOrder = 2
        let secondCategory = Lume.Category(apiId: "2", name: "Sports", parentId: 0, type: .live, playlist: first)
        secondCategory.sortOrder = 1
        let thirdCategory = Lume.Category(apiId: "3", name: "Movies", parentId: 0, type: .live, playlist: second)
        let fileShareCategory = Lume.Category(apiId: "4", name: "Files", parentId: 0, type: .live, playlist: fileShare)
        for category in [firstCategory, secondCategory, thirdCategory, fileShareCategory] {
            context.insert(category)
        }
        try context.save()

        let groups = LiveTVCategoryMemo().groups(
            categories: [firstCategory, secondCategory, thirdCategory, fileShareCategory],
            playlists: [first, second, fileShare],
            isPremium: false,
            sort: .playlist,
            restriction: ContentRestriction()
        )

        #expect(groups.map(\.title) == ["First Provider", "Second Provider"])
        #expect(groups.map { $0.sections.map(\.title) } == [["Sports", "News"], ["Movies"]])
        #expect(groups.map(\.isLocked) == [false, true])
    }
}
