import XCTest
@MainActor
final class VMHarnessUITests: XCTestCase {
    func testActualBundledBIOSExecutesAndStopReleasesSurface() {
        continueAfterFailure = false
        let app=XCUIApplication();app.launch()
        app.buttons["vm.start"].tap()
        let instructions=app.staticTexts["vm.instructions"]
        let actualExecution=NSPredicate(format:"label MATCHES %@", "[1-9][0-9]{5,}")
        expectation(for:actualExecution,evaluatedWith:instructions);waitForExpectations(timeout:40)
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("Actual BIOS running"))
        let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Actual pinned v86 BIOS in system WKWebView, no guest";capture.lifetime = .keepAlways;add(capture)
        app.buttons["vm.stop"].tap()
        XCTAssertTrue(app.buttons["vm.start"].isEnabled)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("no guest state saved"))
    }
    func testBackgroundStopsWithoutAutomaticRestart() {
        let app=XCUIApplication();app.launch();app.buttons["vm.start"].tap()
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.buttons["vm.start"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["vm.start"].isEnabled);XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("WebKit teardown requested"), "Must observe lifecycle teardown, not a fresh app launch")
    }
}
