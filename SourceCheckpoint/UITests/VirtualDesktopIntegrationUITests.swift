import XCTest

@MainActor
final class VirtualDesktopIntegrationUITests: XCTestCase {
    func testActualGuestFileAndCheckpointThenSafeClosePreservesDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let composer = app.textViews["composer.input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap(); composer.typeText("Keep this desktop task")
        app.buttons["history.open"].tap()
        let customize = app.buttons["workspace.route.customize"]
        reveal(customize, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        customize.tap()
        let devices = app.staticTexts["Devices"].firstMatch
        reveal(devices, in: app.collectionViews.firstMatch); devices.tap()
        let desktop = app.buttons["desktop.open"]
        XCTAssertTrue(desktop.waitForExistence(timeout: 5)); desktop.tap()
        app.buttons["Live diagnostics"].tap()
        let console = app.staticTexts["desktop.console"]
        let ready = NSPredicate(format: "label CONTAINS %@", "ORIVYN_DESKTOP_SHELL_READY_v1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: console)], timeout: 150), .completed)
        let input = app.textFields["desktop.input"]
        input.tap(); input.typeText("echo APP_GUEST_319 > /tmp/home/app.txt; cat /tmp/home/app.txt > /dev/ttyS0")
        app.buttons["desktop.input.send"].tap()
        let wrote = NSPredicate(format: "label CONTAINS %@", "APP_GUEST_319")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: wrote, object: console)], timeout: 40), .completed)
        app.buttons["desktop.checkpoint.save"].tap()
        let saved = NSPredicate(format: "label CONTAINS %@", "Checkpoint verified and saved")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: app.staticTexts["desktop.checkpoint.status"])], timeout: 60), .completed)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Production guest file and saved checkpoint"; image.lifetime = .keepAlways; add(image)
        app.buttons["desktop.close"].tap()
        XCTAssertTrue(app.buttons["desktop.open"].waitForExistence(timeout: 30))
        app.navigationBars.buttons["Customize"].firstMatch.tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(composer.value as? String, "Keep this desktop task")
    }
}
