import XCTest

@MainActor
final class OrivynIntegrationUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
    }
    func testIncomingTextRequiresReviewAndCancelPreservesDraft() {
        let draft = app.textViews["composer.input"]
        draft.tap(); draft.typeText("Keep my draft")
        app.open(URL(string: "orivyn://compose?text=Incoming%20text")!)
        let review = app.buttons["incoming.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        review.tap()
        XCTAssertEqual(app.textViews["incoming.text"].value as? String, "Incoming text")
        app.buttons["incoming.cancel"].tap()
        XCTAssertEqual(draft.value as? String, "Keep my draft")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
    }
    func testIncomingTextAppendsOnlyAfterReviewAndDoesNotSend() {
        let draft = app.textViews["composer.input"]
        draft.tap(); draft.typeText("Existing draft")
        app.open(URL(string: "orivyn://compose?text=Shared%20idea")!)
        XCTAssertTrue(app.buttons["incoming.review"].waitForExistence(timeout: 8))
        app.buttons["incoming.review"].tap()
        app.buttons["incoming.accept"].tap()
        XCTAssertEqual(draft.value as? String, "Existing draft\n\nShared idea")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch.exists)
    }
    func testSecondIncomingLinkCannotReplacePendingText() {
        app.open(URL(string: "orivyn://compose?text=First%20request")!)
        XCTAssertTrue(app.buttons["incoming.review"].waitForExistence(timeout: 8))
        app.open(URL(string: "orivyn://compose?text=Second%20request")!)
        app.buttons["incoming.review"].tap()
        XCTAssertEqual(app.textViews["incoming.text"].value as? String, "First request")
        app.buttons["incoming.cancel"].tap()
    }
    func testReminderFormCancellationPreservesComposer() {
        let draft = app.textViews["composer.input"]
        draft.tap(); draft.typeText("Keep this thought")
        openScheduled()
        app.buttons["reminder.new"].tap()
        XCTAssertTrue(app.textFields["reminder.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reminder.schedule"].isEnabled)
        app.textFields["reminder.title"].tap(); app.textFields["reminder.title"].typeText("Do not schedule")
        app.buttons["reminder.form.cancel"].tap()
        app.buttons["workspace.menu"].tap()
        app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(draft.value as? String, "Keep this thought")
    }
    func testActualLocalReminderSurvivesRelaunchAndCanBeCanceled() {
        let title = "Orivyn reminder " + String(UUID().uuidString.prefix(8))
        openScheduled(); app.buttons["reminder.new"].tap()
        let field = app.textFields["reminder.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(title))
        app.buttons["reminder.schedule"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.staticTexts[String(title)].waitForExistence(timeout: 15))
        capture("Orivyn build 5 actual local reminder scheduled")
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10)); openScheduled()
        XCTAssertTrue(app.staticTexts[String(title)].waitForExistence(timeout: 10))
        let cell = app.cells.containing(.staticText, identifier: String(title)).firstMatch
        let cancel = cell.buttons["Cancel reminder"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.staticTexts[String(title)].waitForNonExistence(timeout: 10))
    }
    private func openScheduled() {
        app.buttons["history.open"].tap()
        let row = app.buttons["workspace.route.scheduled"]
        reveal(row, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        row.tap(); XCTAssertTrue(app.navigationBars["Scheduled"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminder.new"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
