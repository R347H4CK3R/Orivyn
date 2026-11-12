import XCTest

@MainActor
final class NativeToolsUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let draft = app.textViews["composer.input"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10)); draft.tap(); draft.typeText("Keep this conversation draft")
    }

    func testMailDraftIsEditableWithoutSilentSendAndBackPreservesChat() {
        openTool("Email")
        let subject = app.textFields["mail.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5)); subject.tap(); subject.typeText("An unsent idea")
        XCTAssertTrue(app.buttons["mail.review"].exists)
        capture("Orivyn native mail draft before review")
        returnToChat()
    }

    func testCalendarUsesActualEventEditorAndCancelPreservesChat() {
        openTool("Calendar")
        let title = app.textFields["calendar.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Do not save this test event")
        app.buttons["calendar.review"].tap()
        let cancel = app.navigationBars.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        capture("Orivyn actual system calendar editor")
        cancel.tap()
        let discard = app.buttons["Discard Changes"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, "Do not save this test event")
        returnToChat()
    }

    func testBrowserRejectsUnsafeSchemeThenOpensActualSafariAndReturns() {
        openTool("Browser")
        let address = app.textFields["browser.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5)); address.tap(); address.typeText("javascript:alert(1)")
        XCTAssertFalse(app.buttons["browser.open"].isEnabled)
        address.tap(); address.press(forDuration: 1)
        // Clear through the field's standard select-all keyboard action, not app internals.
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap(); address.typeText(XCUIKeyboardKey.delete.rawValue) }
        else { address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "javascript:alert(1)".count)) }
        address.typeText("https://example.com")
        XCTAssertTrue(app.buttons["browser.open"].isEnabled); app.buttons["browser.open"].tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15)); capture("Orivyn actual Safari browser"); done.tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5)); returnToChat()
    }

    func testLocationRequestsOnlyOnTapThenClearsActualSimulatorResult() {
        openTool("Location")
        let request = app.buttons["location.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["location.coordinates"].exists)
        request.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let coordinates = app.staticTexts["location.coordinates"]
        XCTAssertTrue(coordinates.waitForExistence(timeout: 35))
        XCTAssertTrue(coordinates.label.contains("37.3349"), "Use declared simulator coordinates, never a fake in-app location result.")
        capture("Orivyn actual Core Location simulator result")
        app.buttons["location.clear"].tap()
        XCTAssertTrue(coordinates.waitForNonExistence(timeout: 5)); returnToChat()
    }

    private func openTool(_ title: String) {
        app.buttons["history.open"].tap()
        let row = app.buttons["workspace.route.customize"]
        reveal(row, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        row.tap(); XCTAssertTrue(app.navigationBars["Customize"].waitForExistence(timeout: 5))
        let tool = app.staticTexts[title].firstMatch
        reveal(tool, in: app.collectionViews.firstMatch)
        tool.tap()
    }
    private func returnToChat() {
        let back = app.navigationBars.buttons["Customize"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Keep this conversation draft")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
    }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
