import XCTest

/// Native interaction with synthetic durable task records. No inference proof.
@MainActor
final class ChatLocalTaskUITests: XCTestCase {
    private let answered = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01"
    private let interrupted = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02"
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "chat-local-tasks"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["fixture.chatTasks.notice"].exists)
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        return app
    }
    private func expand(_ app: XCUIApplication) {
        let group = app.descendants(matching: .any).matching(identifier: "chat.task.list").firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertTrue(group.isHittable); group.tap()
        capture(app, "Expanded task card hierarchy")
        XCTAssertTrue(app.scrollViews["chat.task.records"].waitForExistence(timeout: 5))
    }
    private func inspect(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons["chat.task.inspect." + id]
        reveal(button, in: app.scrollViews["chat.task.records"])
        button.tap()
        XCTAssertTrue(app.textViews["agent.goal"].waitForExistence(timeout: 5))
        capture(app, "Opened saved task " + id)
    }
    func testSavedAnswerInspectionPreservesChatDraftAndEvidence() {
        let app = launch()
        let composer = app.textViews["composer.input"]
        XCTAssertEqual(composer.value as? String, "Keep this synthetic draft")
        expand(app)
        inspect(app, answered)
        let form = app.collectionViews.firstMatch
        let answer = app.staticTexts["agent.answer"]
        reveal(app.staticTexts["agent.state.value"], in: form)
        XCTAssertEqual(app.staticTexts["agent.state.value"].label, "State, answered")
        reveal(app.buttons["agent.run"], in: form)
        XCTAssertFalse(app.buttons["agent.run"].isEnabled)
        reveal(answer, in: form)
        XCTAssertEqual(answer.label, "SYNTHETIC MODEL ANSWER - NOT INFERENCE")
        app.buttons["chat.task.close"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Keep this synthetic draft")
        let evidence = app.staticTexts["chat.task.evidence." + answered + ":1"]
        let disclosure = app.descendants(matching: .any).matching(identifier: "chat.task.operation." + answered + ":1").firstMatch
        reveal(disclosure, in: app.scrollViews["chat.task.records"]); disclosure.tap()
        reveal(evidence, in: app.scrollViews["chat.task.records"])
        XCTAssertTrue(evidence.label.contains("SYNTHETIC LOCAL EVIDENCE - NO TOOL EXECUTED"))
        XCTAssertTrue(evidence.label.contains("capabilities"))
        capture(app, "Synthetic saved task evidence in actual chat")
    }
    func testResumeWithoutLocalModelRejectsAndPreservesInterruptedState() {
        let app = launch(); expand(app); inspect(app, interrupted)
        let form = app.collectionViews.firstMatch
        let resume = app.buttons["agent.run"]
        reveal(resume, in: form)
        XCTAssertEqual(resume.label, "Resume")
        XCTAssertEqual(app.staticTexts["agent.state.value"].label, "State, interrupted")
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        XCTAssertTrue(resume.isEnabled); resume.tap()
        let error = app.staticTexts["agent.error"]
        reveal(error, in: form)
        XCTAssertEqual(error.label, "Select an installed local model first. Local tasks never switch to an online endpoint.")
        reveal(resume, in: form)
        XCTAssertEqual(app.staticTexts["agent.state.value"].label, "State, interrupted")
        XCTAssertEqual(app.staticTexts["agent.steps.value"].label, "Read-only tool steps, 1/6")
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        app.buttons["chat.task.close"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Keep this synthetic draft")
        capture(app, "No-model resume rejection - not successful execution")
    }
    func testDifferentChatCannotInspectOrResumeOriginTaskThroughManualPanel() {
        let app = launch(); expand(app)
        XCTAssertTrue(app.buttons["chat.task.inspect." + answered].exists)
        app.buttons["fixture.history.b"].tap()
        let list = app.descendants(matching: .any).matching(identifier: "chat.task.list").firstMatch
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: list)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 5), .completed)
        app.buttons["history.open"].tap()
        let studio = app.buttons["workspace.route.studio"]
        reveal(studio, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        studio.tap()
        XCTAssertTrue(app.buttons["agent.open"].waitForExistence(timeout: 5)); app.buttons["agent.open"].tap()
        let form = app.collectionViews.firstMatch
        let saved = app.buttons["agent.saved." + interrupted]
        reveal(saved, in: form); saved.tap()
        let error = app.staticTexts["agent.error"]
        reveal(error, in: form)
        XCTAssertEqual(error.label, "The task no longer owns its model resources. Resume explicitly when ready.")
        XCTAssertFalse(app.buttons["agent.run"].exists)
        XCTAssertFalse(app.staticTexts["agent.answer"].exists)
        capture(app, "Cross-chat origin rejection through actual manual task panel")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}
