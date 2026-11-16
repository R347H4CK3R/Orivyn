import XCTest

/// Scripted typed suggestion through production validation; not model-quality proof.
@MainActor
final class ChatPluginSuggestionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "plugin-suggestion"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.plugin.notice"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["fixture.plugin.calls"].label, "Tool calls: 0 · Checks: 1")
        XCTAssertTrue(app.buttons["chat.pluginSuggestion.review"].waitForExistence(timeout: 5))
        return app
    }
    func testTypedSuggestionOpensExactReviewWithoutDispatchAndIsConsumed() {
        let app = launch()
        XCTAssertEqual(app.staticTexts["chat.pluginSuggestion.status"].label, "Suggested call · not executed")
        app.buttons["chat.pluginSuggestion.review"].tap()
        let arguments = app.textViews["plugin.arguments"]
        XCTAssertTrue(arguments.waitForExistence(timeout: 5))
        let text = arguments.value as? String ?? ""
        XCTAssertTrue(text.contains("synthetic query")); XCTAssertTrue(text.contains("query"))
        XCTAssertFalse(app.buttons["plugin.run"].exists)
        let form = app.collectionViews.firstMatch
        reveal(app.buttons["plugin.review"], in: form)
        app.buttons["plugin.review"].tap()
        reveal(app.staticTexts["https://example.invalid/mcp"], in: form)
        XCTAssertTrue(app.staticTexts["https://example.invalid/mcp"].exists)
        XCTAssertTrue(app.staticTexts["fixture.search"].firstMatch.exists)
        reveal(app.buttons["plugin.run"], in: form)
        XCTAssertTrue(app.buttons["plugin.run"].isEnabled)
        capture(app, "Synthetic typed suggestion exact review - Run not tapped")
        app.buttons["chat.pluginSuggestion.close"].tap()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Preserve this synthetic draft")
        XCTAssertFalse(app.buttons["chat.pluginSuggestion.review"].exists)
        app.buttons["fixture.plugin.check"].tap()
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Tool calls: 0 · Checks: 2"),
                                               object: app.staticTexts["fixture.plugin.calls"])
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 5), .completed)
    }
    func testConversationChangeInvalidatesTypedSuggestionWithoutDispatch() {
        let app = launch()
        app.buttons["fixture.history.b"].tap()
        let review = app.buttons["chat.pluginSuggestion.review"]
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 5), .completed)
        XCTAssertFalse(app.textViews["plugin.arguments"].exists)
        app.buttons["fixture.plugin.check"].tap()
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Tool calls: 0 · Checks: 2"),
                                               object: app.staticTexts["fixture.plugin.calls"])
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 5), .completed)
        capture(app, "Cross-chat suggestion invalidation - no dispatch")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
}
