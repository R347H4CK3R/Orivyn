import XCTest

@MainActor
final class SelectedTextExportUITests: XCTestCase {
    func testSelectionReviewAndReturnWithoutSaving() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        app.buttons["history.open"].tap()
        app.buttons["history.new"].tap()
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        let entry = app.buttons["settings.export-text"]
        reveal(entry, in: app.collectionViews.firstMatch)
        entry.tap()
        let prepare = app.buttons["text-export.prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        XCTAssertFalse(prepare.isEnabled)
        let choice = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "text-export.choice.")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertTrue(prepare.isEnabled); prepare.tap()
        let summary = app.staticTexts["text-export.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 conversations"))
        XCTAssertTrue(summary.label.contains("0 messages"))
        XCTAssertTrue(app.buttons["text-export.save"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Selected text snapshot review without save"
        capture.lifetime = .keepAlways; add(capture)
        app.buttons["text-export.change"].tap()
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        XCTAssertTrue(prepare.isEnabled, "Returning to selection preserves the chosen record")
        XCTAssertFalse(app.buttons["text-export.save"].exists)
    }
}
