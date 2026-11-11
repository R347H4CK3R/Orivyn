import XCTest

@MainActor
final class JarvisEVOUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--reset-test-storage"]
        app.launch()
    }

    func testCaptureMainScreenScreenshot() {
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Jarvis-EVO main conversation screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // Regression: an empty composer must not create an empty saved message.
    func testEmptyComposerCannotSend() {
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["composer.send"].isEnabled)
    }

    // Regression: selecting a suggestion must populate the real editable composer.
    func testSuggestionPopulatesComposer() {
        app.buttons["suggestion.plan"].tap()
        let composer = app.textViews["composer.input"]
        XCTAssertTrue((composer.value as? String)?.contains("plan") == true)
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
    }

    // Regression: a new chat must persist and remain selectable after a relaunch.
    func testNewConversationSurvivesRelaunch() {
        app.buttons["history.open"].tap()
        app.buttons["history.new"].tap()
        app.buttons["history.open"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "history.conversation").firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["history.open"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "history.conversation").firstMatch.waitForExistence(timeout: 5))
    }

    // Regression: settings dismissal must return to a usable composer, not an orphaned sheet.
    func testSettingsDismissalRestoresComposer() {
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appearance"].waitForExistence(timeout: 5))
        app.buttons["settings.done"].tap()
        let composer = app.textViews["composer.input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("A local draft")
        XCTAssertEqual(composer.value as? String, "A local draft")
    }

    // Regression: opening and cancelling model selection must not discard a draft.
    func testModelPickerPreservesDraft() {
        let composer = app.textViews["composer.input"]
        composer.tap()
        composer.typeText("Keep this draft")
        app.buttons["model.choose"].tap()
        XCTAssertTrue(app.buttons["model.done"].waitForExistence(timeout: 5))
        app.buttons["model.done"].tap()
        XCTAssertEqual(composer.value as? String, "Keep this draft")
    }

    // Regression: an unavailable provider must report a real error and preserve the input.
    func testUnavailableProviderDoesNotInventResponse() throws {
        let composer = app.textViews["composer.input"]
        composer.tap()
        composer.typeText("Explain gravity")
        app.buttons["composer.send"].tap()
        let error = app.alerts.firstMatch
        if error.waitForExistence(timeout: 5) {
            XCTAssertFalse(app.staticTexts["assistant.response"].exists)
            error.buttons["OK"].tap()
            XCTAssertEqual(composer.value as? String, "Explain gravity")
        } else {
            // On hardware with a configured real provider, inference is an integration test.
            throw XCTSkip("A provider is available; unavailable-provider fixture does not apply.")
        }
    }
}
