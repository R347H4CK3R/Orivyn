import XCTest

@MainActor
final class VerifiedLocalReadUITests: XCTestCase {
    func testSelectedAppAndModelReadsCompleteWithoutInstalledModel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        app.buttons["history.open"].tap()
        let studio = app.buttons["workspace.route.studio"]
        reveal(studio, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        studio.tap()
        let open = app.buttons["verified.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let create = app.buttons["verified.create"]
        reveal(create, in: app.collectionViews.firstMatch)
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let run = app.buttons["verified.run"]
        reveal(run, in: app.collectionViews.firstMatch); run.tap()
        let state = app.staticTexts["verified.state"]
        let complete = NSPredicate(format: "label == %@", "State: complete")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: state)], timeout: 10), .completed)
        let report = app.staticTexts["verified.report"]
        XCTAssertTrue(report.label.contains("Orivyn"))
        XCTAssertTrue(report.label.contains("totalInstalled"))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Deterministic app and installed-model reads"; image.lifetime = .keepAlways; add(image)
    }
}
