import XCTest

/// Uses the native Photos picker and a PNG seeded with simctl addmedia by CI.
/// The image is controlled test input, not an assistant response or an OCR stub.
@MainActor
final class JarvisEVOAttachmentUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
    }

    func testPhotosCancellationKeepsDraftAndAllowsFilesAfterwards() {
        let input = app.textViews["composer.input"]
        input.tap(); input.typeText("Keep the selected idea")
        app.buttons["composer.attach"].tap()
        app.buttons["attachment.photos"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertEqual(input.value as? String, "Keep the selected idea")
        app.buttons["composer.attach"].tap()
        app.buttons["attachment.files"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertEqual(input.value as? String, "Keep the selected idea")
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
    }

    func testRealPhotoImportShowsRecognizedTextAndSafeSharingChoices() {
        app.buttons["composer.attach"].tap()
        app.buttons["attachment.photos"].tap()
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo,' OR label BEGINSWITH[c] 'Photo ' OR label BEGINSWITH[c] 'Screenshot' ")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "The known fixture must exist in the real simulator photo library.")
        photo.tap()
        let addButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add'")).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5)); addButton.tap()
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment.preview.'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        preview.tap()
        XCTAssertTrue(app.images["attachment.image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["attachment.ocr.notice"].exists)
        XCTAssertTrue(app.staticTexts["attachment.ocr.text"].label.contains("JARVIS 42"), "This assertion uses real on-device Vision OCR.")
        XCTAssertTrue(app.buttons["attachment.share.clean"].exists)
        app.buttons["attachment.share.original"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'GPS'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Real imported fixture image and on-device OCR"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["attachment.preview.done"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment.remove.'")).firstMatch.tap()
        XCTAssertFalse(preview.exists)
        XCTAssertTrue(app.buttons["composer.voice"].exists)
    }
}
