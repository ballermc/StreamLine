import XCTest

/// End-to-end Stalker (Ministra) portal flow against the local example IPTV
/// server (`IPTVExampleServer`, http://localhost:8080). Add the portal through
/// the login form, let the auto-sync run the full import, then verify Live TV
/// shows synced channels.
///
/// Prerequisites:
///  - The example server is running: `cd IPTVExampleServer && npm start`.
///  - Run on a simulator where the app has no playlists so the root login form
///    appears (or it falls back to adding via Settings).
final class StalkerPortalFlowTests: XCTestCase {
    private let portalURL = "http://localhost:8080/c/"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStalkerPortalSyncsAndShowsChannels() {
        let app = XCUIApplication()
        launchAndOpenAddForm(app)
        addStalkerPortal(app)
        syncAddedPortal(app)
        dismissSettingsToTabBar(app)
        app.tabBars.buttons["Live TV"].tap()
        assertLiveTVShowsContent(app)
    }

    // MARK: - Steps

    /// Launches the app and opens the add-playlist form.
    private func launchAndOpenAddForm(_ app: XCUIApplication) {
        // `-ui-testing` disables CloudKit (which hard-crashes on the un-entitled
        // test binary) and seeds an empty placeholder playlist, so the app opens
        // on the tab bar — we add the portal through Settings.
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // Fresh install shows the login form as root; otherwise add via Settings.
        if app.tabBars.firstMatch.waitForExistence(timeout: 5) {
            app.settingsToolbarButton.tap()
            XCTAssertTrue(app.openPlaylistsFromSettingsRoot(), "Settings › Playlists did not open")
            let addButton = app.buttons["Add Playlist"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 3))
            addButton.tap()
        }
    }

    /// Fills the Stalker form and submits it, waiting for the portal to be accepted.
    private func addStalkerPortal(_ app: XCUIApplication) {
        let stalkerSegment = app.buttons["Stalker"]
        XCTAssertTrue(stalkerSegment.waitForExistence(timeout: 5))
        stalkerSegment.tap()

        let nameField = app.textFields["e.g. My IPTV"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Example Portal")

        let urlField = app.textFields["e.g. http://example.com:8080/c/"]
        urlField.tap()
        urlField.typeText(portalURL + "\n")

        // More than one element can carry the "Add Playlist" label (navigation
        // title vs. submit button), so pick the hittable button.
        let submitCandidates = app.buttons.matching(identifier: "Add Playlist").allElementsBoundByIndex
        guard let addPlaylist = submitCandidates.last(where: { $0.isHittable && $0.isEnabled }) ?? submitCandidates.last else {
            return XCTFail("No Add Playlist button found")
        }
        if !addPlaylist.isHittable { app.swipeUp() }
        addPlaylist.tap()

        XCTAssertTrue(urlField.waitForNonExistence(timeout: 30), "Portal was not accepted")
    }

    /// Dismisses the Settings sheet and waits for the tab bar.
    private func dismissSettingsToTabBar(_ app: XCUIApplication) {
        // iOS Settings is a sheet with no Done button (Done is macOS-only), so
        // dismiss it by dragging its navigation bar down to the bottom edge.
        let settingsNav = app.navigationBars["Playlists"]
        if settingsNav.waitForExistence(timeout: 10) {
            let from = settingsNav.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
            from.press(forDuration: 0.1, thenDragTo: target)
            XCTAssertTrue(settingsNav.waitForNonExistence(timeout: 10), "Settings sheet did not dismiss")
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar not visible")
    }

    /// Syncs the new provider from its own details, without changing a global
    /// active-playlist setting.
    private func syncAddedPortal(_ app: XCUIApplication) {
        if !app.navigationBars["Playlists"].exists {
            XCTAssertTrue(app.openSettingsPlaylists(), "Settings › Playlists did not open")
        }
        let playlistRow = app.staticTexts["Example Portal"]
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 10), "Added portal is not listed in Settings")
        playlistRow.tap()
        XCTAssertTrue(app.navigationBars["Example Portal"].waitForExistence(timeout: 10), "Portal details did not open")
        let syncNow = app.buttons["Sync Now"]
        XCTAssertTrue(app.scrollUntilExists(syncNow), "Sync Now button not found")
        syncNow.tap()
        let startSync = app.buttons["Start Sync"]
        XCTAssertTrue(startSync.waitForExistence(timeout: 10), "Sync sheet didn't open")
        startSync.tap()
        let doneSync = app.buttons["Done"]
        XCTAssertTrue(doneSync.waitForExistence(timeout: 180), "Stalker sync did not complete")
        doneSync.tap()
        app.navigationBars.buttons["Playlists"].tap()
    }

    /// Verifies Live TV lists synced content and attaches a screenshot.
    private func assertLiveTVShowsContent(_ app: XCUIApplication) {
        // Live TV must list synced categories/channels. The catalog's live
        // categories ("NEWS", "SPORTS", …) and channels ("Lume News 24", …) all
        // contain "news" in the news category, so match it case-insensitively.
        let newsElement = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "news")).firstMatch
        XCTAssertTrue(newsElement.waitForExistence(timeout: 120), "No Live TV content after Stalker sync")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "LiveTV-after-stalker-sync"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
