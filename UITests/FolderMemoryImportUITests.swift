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
}
