import XCTest

@MainActor
final class ArchiveRestoreUITests: XCTestCase {
    private let title = "Synthetic ZIP Restore Acceptance"

    func testRealZIPPickerCancelsAndReopensWithoutRestore() {
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app)
        for attempt in 1...2 {
            chooseZIP(app)
            let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
            let cancel = navigation.buttons["Cancel"]
            for _ in 0..<6 where !cancel.exists {
                let back = navigation.buttons["BackButton"]
                guard back.exists else { break }
                back.tap()
            }
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
            screenshot(app, "Actual ZIP picker before cancellation \(attempt)")
            cancel.tap()
            waitAbsent(navigation)
            XCTAssertTrue(app.buttons["archive.choose-zip"].isEnabled)
            XCTAssertFalse(app.buttons["archive.confirm"].exists)
        }
        relaunch(app)
        assertHistoryAbsent(app)
    }

    func testActualZIPSelectionReviewCommitAndRelaunchHistory() {
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app)
        selectFixtureZIP(app)
        assertReview(app)
        commitPrepared(app)
        relaunch(app)
        assertRestoredHistory(app)
    }

    func testPreparedZIPSurvivesRelaunchButDoesNotActivateUntilConfirmed() {
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app)
        selectFixtureZIP(app)
        assertReview(app)
        relaunch(app)
        assertHistoryAbsent(app)
        openRestore(app)
        let refresh = app.buttons["archive.refresh-retained"]
        reveal(refresh, in: app.collectionViews.firstMatch)
        refresh.tap()
        let retained = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Review 1 conversations")).firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout: 30), app.debugDescription)
        reveal(retained, in: app.collectionViews.firstMatch)
        retained.tap()
        assertReview(app)
        screenshot(app, "Retained ZIP preparation reviewed after relaunch")
        commitPrepared(app)
        relaunch(app)
        assertRestoredHistory(app)
    }

    func testRetainedMediaInventoryRemainsReadOnlyAfterCommitAndRelaunch() {
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app); selectFixtureZIP(app); assertReview(app)
        let inspect = app.buttons["archive.inspect-media"]
        tapUnobscured(inspect, in: app, towardEnd: false)
        assertInventoryLoaded(app)
        let summary = app.staticTexts["archive.media-summary"]
        reveal(summary, in: app.collectionViews.firstMatch)
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 retained reference records")).firstMatch.exists)
        screenshot(app, "Retained media inventory before restore")
        reveal(app.buttons["archive.confirm"], in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(app.buttons["archive.confirm"].exists, "Inventory must not commit history")
        commitPrepared(app); relaunch(app); openRestore(app)
        let refresh = app.buttons["archive.refresh-media"]
        tapUnobscured(refresh, in: app)
        let retained = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Inspect retained media")).firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout: 30))
        tapUnobscured(retained, in: app)
        assertInventoryLoaded(app)
        reveal(summary, in: app.collectionViews.firstMatch)
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["archive.confirm"].exists, "Committed inventory must not become a restore proposal")
        screenshot(app, "Retained media inventory after relaunch")
    }

    /// XCTest can call a row under iOS's translucent navigation bar hittable.
    /// Require its full frame inside the unobscured List viewport before tapping.
    private func tapUnobscured(_ target: XCUIElement, in app: XCUIApplication,
                               towardEnd: Bool = true) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let navigation = app.navigationBars.firstMatch
        for _ in 0..<12 {
            let top = max(list.frame.minY, navigation.exists ? navigation.frame.maxY : list.frame.minY) + 12
            let bottom = list.frame.maxY - 12
            var down = towardEnd
            if target.exists && !target.frame.isEmpty {
                if target.frame.minY > top && target.frame.maxY < bottom && target.isHittable && target.isEnabled {
                    attachHierarchy(app, "Unobscured inventory control before tap")
                    screenshot(app, "Unobscured inventory control before tap")
                    target.tap()
                    return
                }
                if target.frame.minY <= top { down = false }
                else if target.frame.maxY >= bottom { down = true }
            }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.65 : 0.4))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.4 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Inventory control must be enabled and inside the unobscured viewport. " + app.debugDescription)
    }
    private func assertInventoryLoaded(_ app: XCUIApplication) {
        let status = app.staticTexts["archive.status"]
        reveal(status, in: app.collectionViews.firstMatch, towardEnd: false)
        let loaded = NSPredicate(format: "label == %@", "Read-only inventory loaded. No media was linked or activated.")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: status)], timeout: 30), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
        attachHierarchy(app, "Verified read-only inventory loaded")
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func openRestore(_ app: XCUIApplication) {
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        let link = app.buttons["settings.import-chatgpt-zip"]
        reveal(link, in: app.collectionViews.firstMatch)
        XCTAssertTrue(link.isEnabled)
        link.tap()
        XCTAssertTrue(app.buttons["archive.choose-zip"].waitForExistence(timeout: 10))
    }
    private func chooseZIP(_ app: XCUIApplication) {
        let choose = app.buttons["archive.choose-zip"]
        reveal(choose, in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(choose.isEnabled)
        choose.tap()
        XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func selectFixtureZIP(_ app: XCUIApplication) {
        chooseZIP(app)
        let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        // Follow the real Files provider UI. No selected URL is injected into Orivyn.
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        let onMyPhone = app.descendants(matching: .any).matching(identifier: "On My iPhone").firstMatch
        for _ in 0..<6 where !onMyPhone.exists {
            let back = navigation.buttons["BackButton"]
            guard back.exists else { break }
            back.tap()
        }
        XCTAssertTrue(onMyPhone.waitForExistence(timeout: 10), app.debugDescription)
        onMyPhone.tap()
        tapLocation("Archive Fixture", app)
        // Files exposes a filename StaticText separately from its selectable tile.
        // The first native run tapped that label without selecting the document.
        // Select the containing file cell, not an arbitrary descendant label.
        let file = app.cells.containing(.staticText, identifier: "Synthetic ChatGPT Backup.zip").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(file.isEnabled, "Synthetic ZIP tile must be selectable: \(app.debugDescription)")
        XCTAssertTrue(file.isHittable, "Synthetic ZIP tile must be visible: \(app.debugDescription)")
        attachHierarchy(app, "Files ZIP tile before selection")
        screenshot(app, "Files ZIP tile before selection")
        file.tap()
        attachHierarchy(app, "Files ZIP tile after selection")
        screenshot(app, "Files ZIP tile after selection")
        waitAbsent(navigation, timeout: 15)
    }
    private func tapLocation(_ name: String, _ app: XCUIApplication) {
        let item = app.descendants(matching: .any).matching(identifier: name).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        item.tap()
    }
    private func assertReview(_ app: XCUIApplication) {
        let confirm = app.buttons["archive.confirm"]
        let counts = app.staticTexts["1 conversations · 2 messages"]
        reveal(counts, in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(counts.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(counts.exists, app.debugDescription)
        let unresolved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 retained unlinked reference records")).firstMatch
        XCTAssertTrue(unresolved.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
        // Extra truthful disclosures can move the confirmation row below the
        // lazy List viewport. Reveal it; do not equate offscreen with missing.
        reveal(confirm, in: app.collectionViews.firstMatch)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        screenshot(app, "Actual ZIP review before explicit commit")
    }
    private func commitPrepared(_ app: XCUIApplication) {
        let confirm = app.buttons["archive.confirm"]
        reveal(confirm, in: app.collectionViews.firstMatch)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        waitAbsent(confirm, timeout: 60)
        let status = app.staticTexts["archive.status"]
        reveal(status, in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(status.label.contains("Restore receipt verified: 1 added"), app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
        screenshot(app, "Committed ZIP restore receipt")
    }
    private func assertHistoryAbsent(_ app: XCUIApplication) {
        app.buttons["history.open"].tap()
        let rows = app.buttons.matching(identifier: "history.conversation").matching(NSPredicate(format: "label == %@", title))
        XCTAssertEqual(rows.count, 0, "Preparation or cancellation must not activate history")
        app.buttons["history.close"].tap()
    }
    private func assertRestoredHistory(_ app: XCUIApplication) {
        app.buttons["history.open"].tap()
        let rows = app.buttons.matching(identifier: "history.conversation").matching(NSPredicate(format: "label == %@", title))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(rows.count, 1, "The restored conversation must not be duplicated")
        reveal(rows.firstMatch, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic ZIP acceptance question."].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Synthetic ZIP acceptance answer."].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.textViews["composer.input"].isEnabled)
        screenshot(app, "Restored conversation messages after relaunch")
    }
    private func waitAbsent(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let absent = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: absent, object: element)], timeout: timeout), .completed)
    }
    private func attachHierarchy(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
