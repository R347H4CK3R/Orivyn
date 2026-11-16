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
        XCTAssertTrue(confirm.waitForExistence(timeout: 60), app.debugDescription)
        let counts = app.staticTexts["1 conversations · 2 messages"]
        reveal(counts, in: app.collectionViews.firstMatch)
        XCTAssertTrue(counts.exists, app.debugDescription)
        let unresolved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 unresolved media records")).firstMatch
        XCTAssertTrue(unresolved.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
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
