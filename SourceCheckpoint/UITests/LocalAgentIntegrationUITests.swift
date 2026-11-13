import XCTest

/// Requires native simulator execution. This is not model-inference proof.
@MainActor
final class LocalAgentIntegrationUITests: XCTestCase {
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
        app.buttons["agent.create"].tap()
        XCTAssertTrue(app.buttons["agent.run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        openTasks(app)
        let saved = app.buttons.containing(.staticText, identifier: goal).firstMatch
        reveal(saved, in: app.collectionViews.firstMatch)
        saved.tap()
        XCTAssertTrue(app.buttons["agent.run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        XCTAssertTrue(app.staticTexts["agent.status"].label.contains("Resume is explicit"))
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
