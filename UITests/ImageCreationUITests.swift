import XCTest

@MainActor
final class ImageCreationUITests: XCTestCase {
    func testImageCreationStartsWithExplicitConceptAndCancelKeepsChatDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let draft = app.textViews["composer.input"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap(); draft.typeText("Keep my image idea private")
        app.buttons["history.open"].tap()
        let images = app.buttons["workspace.route.images"]
        reveal(images, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        images.tap()
        let create = app.buttons["image.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let concept = app.textViews["image.creation.prompt"]
        XCTAssertTrue(concept.waitForExistence(timeout: 5))
        XCTAssertEqual(concept.value as? String, "")
        XCTAssertFalse(app.buttons["image.creation.generate"].isEnabled)
        concept.tap(); concept.typeText("An original illustrated blue kite")
        // Simulator capability absence is truthful, never a generated image fixture.
        if app.staticTexts["image.creation.unavailable"].exists {
            XCTAssertFalse(app.buttons["image.creation.generate"].isEnabled)
        }
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Image creation capability and explicit concept"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["image.creation.cancel"].tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(draft.value as? String, "Keep my image idea private")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch.exists)
    }
}
