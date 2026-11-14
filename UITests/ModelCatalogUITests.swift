import XCTest

@MainActor
final class ModelCatalogUITests: XCTestCase {
    func testFilteringDoesNotHideActiveDownloadCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "model-download"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        let search = app.textFields["model.catalog.search"]
        let list = app.collectionViews.firstMatch
        reveal(search, in: list)
        search.tap(); search.typeText("no catalog matches")
        XCTAssertTrue(app.staticTexts["No matching models. Try a different search or purpose."].waitForExistence(timeout: 5))
        let cancel = app.buttons["model.download.cancel"]
        reveal(cancel, in: list, towardEnd: false)
        XCTAssertTrue(cancel.isHittable); cancel.tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: cancel)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
