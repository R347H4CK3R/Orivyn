import XCTest

@MainActor
final class DeskWorkspaceUITests: XCTestCase {
    func testDeskControllerTruthfullyShowsNoExternalDisplayAndKeepsDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("Keep my workspace thought")
        app.buttons["history.open"].tap()
        let customize = app.buttons["workspace.route.customize"]
        reveal(customize, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        customize.tap()
        let devices = app.staticTexts["Devices"].firstMatch
        reveal(devices, in: app.collectionViews.firstMatch); devices.tap()
        let desk = app.buttons["desk.open"]
        XCTAssertTrue(desk.waitForExistence(timeout: 5)); desk.tap()
        XCTAssertTrue(app.staticTexts["desk.disconnected"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["desk.enabled"].isEnabled)
        XCTAssertFalse(app.staticTexts["desk.connected"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Desk disconnected privacy controls"; capture.lifetime = .keepAlways; add(capture)
        app.navigationBars.buttons["Devices"].firstMatch.tap()
        app.navigationBars.buttons["Customize"].firstMatch.tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(input.value as? String, "Keep my workspace thought")
    }
}
