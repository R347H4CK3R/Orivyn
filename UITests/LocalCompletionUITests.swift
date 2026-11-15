import XCTest

/// Actual review/approval UI only. No Run tap or inference claim.
@MainActor
final class LocalCompletionUITests: XCTestCase {
    func testReviewDiscardApprovalAndRelaunchRequireExplicitRun() {
        continueAfterFailure = false
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch();open(app)
        let goal="Inspect app and Cedar acceptance memory"
        let input=app.textViews["agent.goal"]
        reveal(input,in:app.collectionViews.firstMatch);input.tap();input.typeText(goal)
        for id in ["completion.info","completion.memory"] {
            let toggle=app.switches[id];reveal(toggle,in:app.collectionViews.firstMatch);toggle.tap()
        }
        let query=app.textFields["completion.query"]
        reveal(query,in:app.collectionViews.firstMatch);query.tap();query.typeText("Cedar acceptance")
        prepare(app,goal:goal,query:"Cedar acceptance")
        XCTAssertFalse(input.isEnabled);XCTAssertFalse(query.isEnabled)
        XCTAssertFalse(app.switches["completion.info"].isEnabled)
        XCTAssertFalse(app.switches["completion.memory"].isEnabled)
        XCTAssertFalse(app.buttons["agent.run"].exists);XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        let discard=app.buttons["completion.discard"];reveal(discard,in:app.collectionViews.firstMatch);discard.tap()
        XCTAssertFalse(app.staticTexts["completion.review"].exists)
        reveal(query,in:app.collectionViews.firstMatch);XCTAssertTrue(query.isEnabled)
        query.tap();query.typeText(" revised")
        prepare(app,goal:goal,query:"Cedar acceptance revised")
        app.navigationBars.buttons.element(boundBy:0).tap()
        let tasks=app.buttons["agent.open"];XCTAssertTrue(tasks.waitForExistence(timeout:5));tasks.tap()
        XCTAssertFalse(app.staticTexts["completion.review"].exists)
        XCTAssertFalse(app.buttons["completion.approve"].exists);XCTAssertFalse(app.buttons["agent.run"].exists)
        // Navigation creates a fresh composer. Re-enter exact approved scope.
        reveal(input,in:app.collectionViews.firstMatch);input.tap();input.typeText(goal)
        for id in ["completion.info","completion.memory"] {let t=app.switches[id];reveal(t,in:app.collectionViews.firstMatch);t.tap()}
        reveal(query,in:app.collectionViews.firstMatch);query.tap();query.typeText("Cedar acceptance final")
        prepare(app,goal:goal,query:"Cedar acceptance final")
        capture(app,"Exact review")
        let approve=app.buttons["completion.approve"];reveal(approve,in:app.collectionViews.firstMatch);approve.tap()
        XCTAssertFalse(app.buttons["completion.approve"].exists)
        ready(app);capture(app,"Approved ready without execution")
        app.terminate()
    }
    func testRelaunchPreservesApprovedScopeWithoutExecution() {
        continueAfterFailure = false
        let goal="Inspect app and Cedar acceptance memory"
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch();open(app)
        let saved=app.buttons.containing(.staticText,identifier:goal).firstMatch
        reveal(saved,in:app.collectionViews.firstMatch);saved.tap();ready(app)
        let scope=app.staticTexts["Cedar acceptance final"];reveal(scope,in:app.collectionViews.firstMatch)
        XCTAssertTrue(scope.exists);capture(app,"Restored approved scope without execution")
        app.terminate()
    }
    private func prepare(_ app:XCUIApplication,goal:String,query:String) {
        let button=app.buttons["completion.prepare"];reveal(button,in:app.collectionViews.firstMatch)
        XCTAssertTrue(button.isEnabled);button.tap()
        let review=app.staticTexts["completion.review"];reveal(review,in:app.collectionViews.firstMatch)
        XCTAssertEqual(review.label,goal)
        for label in ["1. Read bundled app information","2. Search saved memory",query,"Maximum matches: 3"] {
            let text=app.staticTexts[label];reveal(text,in:app.collectionViews.firstMatch);XCTAssertTrue(text.exists)
        }
        XCTAssertTrue(app.buttons["completion.approve"].isEnabled)
    }
    private func ready(_ app:XCUIApplication) {
        let run=app.buttons["agent.run"];reveal(run,in:app.collectionViews.firstMatch);XCTAssertTrue(run.isEnabled)
        XCTAssertTrue(app.staticTexts["ready"].exists);XCTAssertTrue(app.staticTexts["0/6"].exists)
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        let status=app.staticTexts["agent.status"].label
        XCTAssertTrue(status.contains("no operation starts automatically") || status.contains("Resume is explicit"))
    }
    private func open(_ app:XCUIApplication) {
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout:20));app.buttons["history.open"].tap()
        let studio=app.buttons["workspace.route.studio"];reveal(studio,in:app.descendants(matching:.any).matching(identifier:"history.list").firstMatch);studio.tap()
        let tasks=app.buttons["agent.open"];XCTAssertTrue(tasks.waitForExistence(timeout:5));tasks.tap()
    }
    private func capture(_ app:XCUIApplication,_ name:String) {
        let image=XCTAttachment(screenshot:app.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        let tree=XCTAttachment(string:app.debugDescription);tree.name=name+" hierarchy";tree.lifetime = .keepAlways;add(tree)
    }
}
