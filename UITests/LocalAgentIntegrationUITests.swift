import XCTest

/// Requires native simulator execution. This is not model-inference proof.
@MainActor
final class LocalAgentIntegrationUITests: XCTestCase {
    func testSendRoutesExactLocalRequestToChecklistWithoutExecuting() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Existing controlled UI provider, not real model-inference proof.
        app.launchArguments = ["--uitesting", "--root-view-fixture", "history-scroll"]
        app.launch()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let goal = "List installed models"
        input.tap(); input.typeText(goal)
        XCTAssertTrue(app.staticTexts["composer.localTask.routeNotice"].exists)
        let send = app.buttons["composer.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let taskGoal = app.textViews["agent.goal"]
        XCTAssertTrue(taskGoal.waitForExistence(timeout: 5))
        XCTAssertEqual(taskGoal.value as? String, goal)
        XCTAssertFalse(app.buttons["agent.run"].exists)
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        let toggle = app.switches["completion.models"]
        reveal(toggle, in: app.collectionViews.firstMatch)
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["chat.localTask.done"].tap()
        XCTAssertEqual(input.value as? String, goal)
    }

    func testChatDraftOpensLocalReviewWithoutCreatingOrRunningTask() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let goal = "Search saved memory for boats"
        input.tap(); input.typeText(goal)
        let review = app.buttons["composer.localTask.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        let taskGoal = app.textViews["agent.goal"]
        XCTAssertTrue(taskGoal.waitForExistence(timeout: 5))
        XCTAssertEqual(taskGoal.value as? String, goal)
        XCTAssertFalse(app.buttons["agent.run"].exists)
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        app.buttons["chat.localTask.done"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, goal)
        // Normal chat remains a separate explicit action.
        XCTAssertTrue(app.buttons["composer.send"].exists)
        review.tap()
        XCTAssertEqual(taskGoal.value as? String, goal)
        XCTAssertFalse(app.buttons["agent.run"].exists)
    }

    func testSavedTaskSurvivesRelaunchWithoutAutomaticExecution() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        openTasks(app)
        let goal = "List installed models without changing anything"
        let input = app.textViews["agent.goal"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText(goal)
        XCTAssertEqual(input.value as? String, goal)
        // Form rows below the expanded plan guidance are lazy and may not exist
        // while the goal editor/keyboard is visible. Reach the actual control.
        let form = app.collectionViews.firstMatch
        let draft = app.buttons["agent.plan.draft"]
        reveal(draft, in: form)
        XCTAssertEqual(draft.label, "Draft plan for review")
        XCTAssertTrue(draft.isEnabled)
        XCTAssertFalse(app.buttons["agent.create"].isHittable)
        // Generic creation is intentionally behind an explicit experimental disclosure.
        let experimental = app.descendants(matching: .any).matching(identifier: "agent.experimental.options").firstMatch
        reveal(experimental, in: form)
        experimental.tap()
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Expanded experimental task accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Expanded experimental task controls"
        expanded.lifetime = .keepAlways
        add(expanded)
        let create = app.buttons["agent.create"]
        reveal(create, in: form)
        XCTAssertTrue(create.isEnabled)
        create.tap()
        reveal(app.buttons["agent.run"], in: form)
        XCTAssertTrue(app.buttons["agent.run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        openTasks(app)
        let saved = app.buttons.containing(.staticText, identifier: goal).firstMatch
        reveal(saved, in: app.collectionViews.firstMatch)
        saved.tap()
        // Selection inserts Current task rows; the lazy form may reset to its top.
        reveal(app.buttons["agent.run"], in: app.collectionViews.firstMatch)
        XCTAssertTrue(app.buttons["agent.run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        XCTAssertTrue(app.staticTexts["agent.status"].label.contains("Resume is explicit"))
        let warning = app.staticTexts["agent.unreviewedWarning"]
        reveal(warning, in: app.collectionViews.firstMatch)
        XCTAssertTrue(warning.label.contains("no approved completion checklist"))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Saved local task requires explicit run"
        image.lifetime = .keepAlways
        add(image)
    }
    private func openTasks(_ app: XCUIApplication) {
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        app.buttons["history.open"].tap()
        let studio = app.buttons["workspace.route.studio"]
        reveal(studio, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        studio.tap()
        let tasks = app.buttons["agent.open"]
        XCTAssertTrue(tasks.waitForExistence(timeout: 5)); tasks.tap()
    }
}
