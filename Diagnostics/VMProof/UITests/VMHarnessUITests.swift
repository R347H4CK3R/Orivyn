import XCTest
@MainActor
final class VMHarnessUITests: XCTestCase {
    func testActualBundledBIOSExecutesAndStopReleasesSurface() {
        continueAfterFailure = false
        let app=XCUIApplication();app.launch()
        app.buttons["vm.start"].tap()
        let instructions=app.staticTexts["vm.instructions"]
        let actualExecution=NSPredicate(format:"label MATCHES %@", "[1-9][0-9]{5,}")
        let execution = XCTNSPredicateExpectation(predicate: actualExecution, object: instructions)
        let result = XCTWaiter.wait(for: [execution], timeout: 40)
        if result != .completed {
            let diagnostics = XCTAttachment(string: app.debugDescription)
            diagnostics.name = "BIOS failure hierarchy and actual status"
            diagnostics.lifetime = .keepAlways; add(diagnostics)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "BIOS failure visible state"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCTAssertEqual(result, .completed, "BIOS did not execute: \(app.staticTexts["vm.status"].label)")
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
