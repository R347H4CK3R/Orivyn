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
        XCTAssertFalse(app.buttons["composer.send"].exists)
        XCTAssertTrue(app.buttons["composer.voice"].isEnabled)
        app.buttons["composer.voice"].tap()
        let error = app.alerts.firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), "Without an installed model, voice must fail preflight before requesting the microphone.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch.exists)
        error.buttons["OK"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "")
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
        reveal(app.buttons.matching(identifier: "history.conversation").firstMatch,
               in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["history.open"].tap()
        reveal(app.buttons.matching(identifier: "history.conversation").firstMatch,
               in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
    }

    // Regression: settings dismissal must return to a usable composer, not an orphaned sheet.
    func testSettingsDismissalRestoresComposer() {
        app.buttons["toolbar.more"].tap()
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

    // Cancelling the real Files picker repeatedly must not discard or disable the draft.
    func testAttachmentPickerCancellationPreservesDraftAfterReopening() {
        let composer = app.textViews["composer.input"]
        composer.tap()
        composer.typeText("Attach a document later")
        for _ in 0..<2 {
            app.buttons["composer.attach"].tap()
            app.buttons["attachment.files"].tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            XCTAssertTrue(composer.waitForExistence(timeout: 5))
            XCTAssertEqual(composer.value as? String, "Attach a document later")
            XCTAssertTrue(app.buttons["composer.send"].isEnabled)
        }
    }

    func testHistoryImportCancellationReturnsToSettingsAndPreservesComposer() {
        let composer = app.textViews["composer.input"]
        composer.tap()
        composer.typeText("Keep this draft during import")
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        let importButton = app.buttons["Import conversation backup"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Backup exported"].exists)
        app.buttons["settings.done"].tap()
        XCTAssertEqual(composer.value as? String, "Keep this draft during import")
    }

}
