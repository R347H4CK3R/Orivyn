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
            enableSwitch(app,id)
        }
        let query=app.textFields["completion.query"]
        reveal(query,in:app.collectionViews.firstMatch);query.tap();query.typeText("Cedar acceptance")
        prepare(app,goal:goal,query:"Cedar acceptance")
        inspect(input,in:app,towardEnd:false);XCTAssertFalse(input.isEnabled)
        for id in ["completion.info","completion.memory"] {
            let toggle=app.switches[id];inspect(toggle,in:app,towardEnd:true)
            XCTAssertFalse(toggle.isEnabled);XCTAssertEqual(toggle.value as? String,"1")
        }
        inspect(query,in:app,towardEnd:true);XCTAssertFalse(query.isEnabled)
        XCTAssertEqual(query.value as? String,"Cedar acceptance")
        XCTAssertFalse(app.buttons["agent.run"].exists);XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        let discard=app.buttons["completion.discard"];reveal(discard,in:app.collectionViews.firstMatch);discard.tap()
        let compose=app.buttons["completion.prepare"];inspect(compose,in:app,towardEnd:false)
        XCTAssertTrue(compose.isEnabled)
        XCTAssertFalse(app.staticTexts["completion.review"].exists)
        reveal(query,in:app.collectionViews.firstMatch);XCTAssertTrue(query.isEnabled)
        query.tap();query.typeText(" revised")
        prepare(app,goal:goal,query:"Cedar acceptance revised")
        app.navigationBars.buttons.element(boundBy:0).tap()
        let tasks=app.buttons["agent.open"];XCTAssertTrue(tasks.waitForExistence(timeout:5));tasks.tap()
        inspect(app.buttons["completion.prepare"],in:app,towardEnd:true)
        XCTAssertFalse(app.staticTexts["completion.review"].exists)
        XCTAssertFalse(app.buttons["completion.approve"].exists);XCTAssertFalse(app.buttons["agent.run"].exists)
        // Navigation creates a fresh composer. Re-enter exact approved scope.
        reveal(input,in:app.collectionViews.firstMatch,towardEnd:false);input.tap();input.typeText(goal)
        for id in ["completion.info","completion.memory"] {enableSwitch(app,id)}
        reveal(query,in:app.collectionViews.firstMatch);query.tap();query.typeText("Cedar acceptance final")
        prepare(app,goal:goal,query:"Cedar acceptance final")
        capture(app,"Exact review")
        let approve=app.buttons["completion.approve"];reveal(approve,in:app.collectionViews.firstMatch);approve.tap()
        XCTAssertFalse(app.buttons["completion.approve"].exists)
        capture(app,"Post approval state identifiers")
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
    /// Materialize disabled Form rows for observation, never for interaction.
    /// `reveal` still requires hittability for every tap/type target.
    private func inspect(_ target:XCUIElement,in app:XCUIApplication,towardEnd:Bool) {
        let list=app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout:5))
        for _ in 0..<12 {
            let top=max(list.frame.minY,app.navigationBars.firstMatch.frame.maxY)+12
            let keyboard=app.keyboards.firstMatch
            let unobscuredBottom=keyboard.exists ? min(app.frame.maxY,keyboard.frame.minY) : app.frame.maxY
            let bottom=min(list.frame.maxY,unobscuredBottom)-34
            if target.exists {
                let frame=target.frame
                if !frame.isEmpty && frame.minY>=top && frame.maxY<=bottom { return }
                if !frame.isEmpty && frame.minY<top { list.swipeDown();continue }
                if !frame.isEmpty && frame.maxY>bottom { list.swipeUp();continue }
            }
            if towardEnd { list.swipeUp() } else { list.swipeDown() }
        }
        capture(app,"Inspection target not materialized")
        XCTFail("Expected unique observation target within visible Form viewport after bounded scrolling.")
    }
    private func enableSwitch(_ app:XCUIApplication,_ id:String) {
        let toggle=app.switches[id];reveal(toggle,in:app.collectionViews.firstMatch)
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? String,"0")
        // Native evidence: SwiftUI exposes the whole row as Switch; its center
        // hits label text. Activate the visible trailing toggle within that row.
        capture(app,"Before enabling " + id)
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        let enabled=NSPredicate(format:"value == %@","1")
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:enabled,object:toggle)],timeout:5),.completed)
        capture(app,"Enabled " + id)
    }
    private func prepare(_ app:XCUIApplication,goal:String,query:String) {
        let button=app.buttons["completion.prepare"];reveal(button,in:app.collectionViews.firstMatch)
        XCTAssertTrue(button.isEnabled);button.tap()
        let review=app.staticTexts["completion.review"];reveal(review,in:app.collectionViews.firstMatch)
        XCTAssertEqual(review.label,goal)
        for label in ["1. Read bundled app information","2. Search saved memory",query] {
            let text=app.staticTexts[label];reveal(text,in:app.collectionViews.firstMatch);XCTAssertTrue(text.exists)
        }
        // Both composer and review intentionally show the limit. The composer
        // is disabled during review; require the single enabled summary label.
        let limits=app.staticTexts.matching(NSPredicate(format:"label == %@ AND enabled == true","Maximum matches: 3"))
        XCTAssertEqual(limits.count,1)
        let limit=limits.element(boundBy:0);reveal(limit,in:app.collectionViews.firstMatch)
        XCTAssertEqual(limit.label,"Maximum matches: 3")
        let composerLimit=app.steppers["Maximum matches: 3"]
        inspect(composerLimit,in:app,towardEnd:false)
        XCTAssertTrue(composerLimit.exists);XCTAssertFalse(composerLimit.isEnabled)
        XCTAssertEqual(composerLimit.value as? String,"3")
        let approve=app.buttons["completion.approve"]
        reveal(approve,in:app.collectionViews.firstMatch);XCTAssertTrue(approve.isEnabled)
    }
    private func ready(_ app:XCUIApplication) {
        let run=app.buttons["agent.run"];reveal(run,in:app.collectionViews.firstMatch);XCTAssertTrue(run.isEnabled)
        let state=app.staticTexts["agent.state.value"]
        inspect(state,in:app,towardEnd:false);XCTAssertEqual(state.label,"State, ready")
        let steps=app.staticTexts["agent.steps.value"];inspect(steps,in:app,towardEnd:true);XCTAssertEqual(steps.label,"Read-only tool steps, 0/6")
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        let statusText=app.staticTexts["agent.status"];inspect(statusText,in:app,towardEnd:true)
        let status=statusText.label
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
