import XCTest

@MainActor
final class FolderMemoryImportUITests: XCTestCase {
    func testRealFolderPickerCanCancelAndReopenWithoutSaving() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        let memory = app.buttons["Saved memory"]
        reveal(memory, in: app.collectionViews.firstMatch); memory.tap()
        let folder = app.buttons["Import a folder"]
        reveal(folder, in: app.collectionViews.firstMatch); folder.tap()
        for attempt in 1...2 {
            let choose = app.buttons["memory.choose-folder"]
            reveal(choose, in: app.collectionViews.firstMatch)
            XCTAssertTrue(choose.isEnabled); choose.tap()
            let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
            XCTAssertTrue(navigation.waitForExistence(timeout: 10), "Real Files folder picker must appear")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Actual folder picker attempt \(attempt)"; shot.lifetime = .keepAlways; add(shot)
            let cancel = navigation.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
            let absent = NSPredicate(format: "exists == false")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: absent, object: navigation)], timeout: 5), .completed)
            XCTAssertTrue(choose.waitForExistence(timeout: 5)); XCTAssertTrue(choose.isEnabled)
            XCTAssertFalse(app.buttons["memory.confirm-folder-import"].exists)
        }
    }
    func testActualFilesFolderSelectionReviewsThenSavesAndPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        openFolderImport(app)
        app.buttons["memory.choose-folder"].tap()
        let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        // Browse the actual iOS Files provider, not an injected selected URL.
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        tapLocation("On My iPhone", app: app)
        tapLocation("Memory Fixture", app: app)
        tapLocation("Memory Import Fixture", app: app)
        let select = navigation.buttons["Open"]
        XCTAssertTrue(select.waitForExistence(timeout: 5), app.debugDescription)
        select.tap()
        let save = app.buttons["memory.confirm-folder-import"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), app.debugDescription)
        let preview = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Synthetic acceptance fact: Cedar trains are preferred.")).firstMatch
        reveal(preview, in: app.collectionViews.firstMatch)
        XCTAssertTrue(preview.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Actual selected folder review before save"; shot.lifetime = .keepAlways; add(shot)
        reveal(save, in: app.collectionViews.firstMatch, towardEnd: false); save.tap()
        let absent = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: absent, object: save)], timeout: 10), .completed)
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["toolbar.more"].tap(); app.buttons["settings.open"].tap()
        let memory = app.buttons["Saved memory"]
        reveal(memory, in: app.collectionViews.firstMatch); memory.tap()
        let persisted = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Cedar trains are preferred")).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 10), app.debugDescription)
    }

    private func openFolderImport(_ app: XCUIApplication) {
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        app.buttons["toolbar.more"].tap(); app.buttons["settings.open"].tap()
        let memory = app.buttons["Saved memory"]
        reveal(memory, in: app.collectionViews.firstMatch); memory.tap()
        let folder = app.buttons["Import a folder"]
        reveal(folder, in: app.collectionViews.firstMatch); folder.tap()
        reveal(app.buttons["memory.choose-folder"], in: app.collectionViews.firstMatch)
    }

    private func tapLocation(_ label: String, app: XCUIApplication) {
        let location = app.descendants(matching: .any).matching(identifier: label).firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 10), app.debugDescription)
        location.tap()
    }

}
