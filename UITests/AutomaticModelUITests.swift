import XCTest

@MainActor
final class AutomaticModelUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
    }

    func testAutomaticModeAndSeparateCellularChoiceSurviveRelaunch() {
        app.buttons["model.choose"].tap()
        let automatic = app.switches["model.automatic"]
        reveal(automatic, in: app.descendants(matching: .any).matching(identifier: "model.list").firstMatch)
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        XCTAssertEqual(automatic.value as? String, "0")
        // iOS 26 exposes a row-sized parent Switch and a nested UISwitch knob.
        // Tapping the parent center lands in the label gap, not the control.
        let knob = automatic.switches.firstMatch
        XCTAssertTrue(knob.exists); knob.tap()
        XCTAssertEqual(automatic.value as? String, "1")
        let cellular = app.switches["model.automatic.cellular"]
        XCTAssertTrue(cellular.waitForExistence(timeout: 5))
        XCTAssertEqual(cellular.value as? String, "0", "Automatic downloads begin with the Wi-Fi policy, not implicit cellular consent.")
        XCTAssertFalse(app.buttons["model.download.cancel"].exists, "Enabling mode alone must not start a download.")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Automatic opt-in with cellular off"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["model.done"].tap()
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        app.buttons["model.choose"].tap()
        reveal(app.switches["model.automatic"], in: app.descendants(matching: .any).matching(identifier: "model.list").firstMatch)
        XCTAssertEqual(app.switches["model.automatic"].value as? String, "1")
        XCTAssertEqual(app.switches["model.automatic.cellular"].value as? String, "0")
    }

    func testDirectToolRequestOpensRealReviewWithoutSendingOrReplacingDraft() {
        let draft = app.textViews["composer.input"]
        draft.tap(); draft.typeText("Open browser")
        let tool = app.buttons["tool.suggestion.browser"]
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        tool.tap()
        XCTAssertTrue(app.textFields["browser.url"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browser.open"].isEnabled, "Opening a tool must not invent a URL or visit a website.")
        app.buttons["tool.review.done"].tap()
        XCTAssertEqual(draft.value as? String, "Open browser")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch.exists)
    }
}
