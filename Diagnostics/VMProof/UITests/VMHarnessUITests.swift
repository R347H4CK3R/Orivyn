import XCTest
@MainActor
final class VMHarnessUITests: XCTestCase {
    func testRealGuestFileSurvivesCheckpointAndFreshAppRead() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); app.buttons["vm.start"].tap()
        // Actual xterm child emits this over the emulated UART. No timer-only readiness.
        let ready = NSPredicate(format: "label CONTAINS %@", "ORIVYN_DESKTOP_SHELL_READY_v1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app.staticTexts["vm.console"])], timeout: 120), .completed, "Real guest terminal did not become ready")
        func command(_ text: String) {
            let field = app.textFields["vm.input"]; field.tap()
            field.typeText(text)
            app.buttons["vm.input.send"].tap()
        }
        command("echo NATIVE_FILE_948 > /tmp/home/native.txt; cat /tmp/home/native.txt > /dev/ttyS0")
        let first = NSPredicate(format: "label CONTAINS %@", "NATIVE_FILE_948")
        let firstResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: first, object: app.staticTexts["vm.console"])], timeout: 35)
        if firstResult != .completed {
            app.buttons["vm.console.switch"].tap(); Thread.sleep(forTimeInterval: 2)
            command("root"); Thread.sleep(forTimeInterval: 2)
            command("cat /tmp/xlogs/session.log >/dev/ttyS0; ps >/dev/ttyS0")
            Thread.sleep(forTimeInterval: 8)
            let debug = XCTAttachment(string: app.debugDescription); debug.name = "Guest failure console and native input state"; debug.lifetime = .keepAlways; add(debug)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Guest failure terminal diagnostic"; image.lifetime = .keepAlways; add(image)
        }
        XCTAssertEqual(firstResult, .completed)
        let desktop = XCTAttachment(screenshot: app.screenshot()); desktop.name = "Actual guest before checkpoint; inspect desktop pixels"; desktop.lifetime = .keepAlways; add(desktop)
        app.buttons["vm.checkpoint.save"].tap()
        let saved = NSPredicate(format: "label CONTAINS %@", "Checkpoint verified and saved")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: app.staticTexts["vm.checkpoint.status"])], timeout: 50), .completed)
        app.terminate(); app.launch(); app.buttons["vm.start"].tap()
        let running = NSPredicate(format: "label CONTAINS %@", "Guest CPU running")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: running, object: app.staticTexts["vm.status"])], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts["vm.console"].label.contains("NATIVE_FILE_948"))
        app.buttons["vm.checkpoint.restore"].tap()
        let restored = NSPredicate(format: "label CONTAINS %@", "Checkpoint verified and restored")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: app.staticTexts["vm.checkpoint.status"])], timeout: 50), .completed)
        app.buttons["vm.resume"].tap()
        command("cat /tmp/home/native.txt > /dev/ttyS0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: first, object: app.staticTexts["vm.console"])], timeout: 30), .completed)
        let restoredImage = XCTAttachment(screenshot: app.screenshot()); restoredImage.name = "Fresh guest read after app relaunch"; restoredImage.lifetime = .keepAlways; add(restoredImage)
        app.buttons["vm.stop"].tap()
    }
    func testGuestInputControlsAreAvailableWithoutClaimingExecution() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["vm.input"].exists)
        XCTAssertFalse(app.buttons["vm.input.send"].isEnabled)
    }
    func testPinnedGuestCPUExecutesAndStopReleasesSurface() {
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
        XCTAssertEqual(result, .completed, "BIOS did not execute: \(app.staticTexts["vm.status"].label). Trace: \(app.staticTexts["vm.diagnostics"].label)")
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("Guest CPU running"))
        let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Pinned maintained guest CPU execution, desktop acceptance still separate";capture.lifetime = .keepAlways;add(capture)
        app.buttons["vm.stop"].tap()
        XCTAssertTrue(app.buttons["vm.start"].isEnabled)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("previous checkpoints retained"))
    }
    func testBackgroundStopsWithoutAutomaticRestart() {
        let app=XCUIApplication();app.launch();app.buttons["vm.start"].tap()
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.buttons["vm.start"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["vm.start"].isEnabled);XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("WebKit teardown requested"), "Must observe lifecycle teardown, not a fresh app launch")
    }
    func testCheckpointSurvivesAppRelaunchAndRequiresResume() {
        let app = XCUIApplication(); app.launch(); app.buttons["vm.start"].tap()
        let running = NSPredicate(format: "label CONTAINS %@", "Guest CPU running")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: running, object: app.staticTexts["vm.status"])], timeout: 35), .completed)
        app.buttons["vm.checkpoint.save"].tap()
        let saved = NSPredicate(format: "label CONTAINS %@", "Checkpoint verified and saved")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: app.staticTexts["vm.checkpoint.status"])], timeout: 35), .completed)
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("paused"))
        app.terminate(); app.launch(); app.buttons["vm.start"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: running, object: app.staticTexts["vm.status"])], timeout: 35), .completed)
        app.buttons["vm.checkpoint.restore"].tap()
        let restored = NSPredicate(format: "label CONTAINS %@", "Checkpoint verified and restored")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: app.staticTexts["vm.checkpoint.status"])], timeout: 35), .completed)
        XCTAssertTrue(app.staticTexts["vm.status"].label.contains("paused"))
        app.buttons["vm.resume"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: running, object: app.staticTexts["vm.status"])], timeout: 10), .completed)
        app.buttons["vm.stop"].tap()
    }

}
