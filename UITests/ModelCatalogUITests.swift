import XCTest

@MainActor
final class ModelCatalogUITests: XCTestCase {
    func testFilteringDoesNotHideActiveDownloadCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "model-download"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        let search = app.textFields["model.catalog.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("no catalog matches")
        XCTAssertTrue(app.staticTexts["No matching models. Try a different search or purpose."].waitForExistence(timeout: 5))
        let cancel = app.buttons["model.download.cancel"]
        XCTAssertTrue(cancel.exists, "Filtering must not remove the active download controls.")
        if !cancel.isHittable { app.swipeDown() }
        XCTAssertTrue(cancel.isHittable); cancel.tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: cancel)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
