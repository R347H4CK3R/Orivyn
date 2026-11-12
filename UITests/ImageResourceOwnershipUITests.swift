import XCTest

@MainActor
final class ImageResourceOwnershipUITests: XCTestCase {
    func testImageFormReservesResourcesAndDismissalRestoresComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let draft = app.textViews["composer.input"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap(); draft.typeText("Keep the draft while making an image")
        app.buttons["history.open"].tap()
        let images = app.buttons["workspace.route.images"]
        reveal(images, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        images.tap()
        let create = app.buttons["image.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.staticTexts["image.creation.resources.ready"].waitForExistence(timeout: 5),
            "The stable image form must own an exclusive lease after releasing cached model resources")
        app.buttons["image.creation.cancel"].tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(draft.value as? String, "Keep the draft while making an image")
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
        XCTAssertFalse(app.buttons["composer.stop"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch.exists)
    }
}
