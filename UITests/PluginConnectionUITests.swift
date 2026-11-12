import XCTest

@MainActor
final class PluginConnectionUITests: XCTestCase {
    func testPluginCredentialIsClearedAfterBackgroundWithoutConnecting() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.buttons["history.open"].waitForExistence(timeout: 10))
        app.buttons["history.open"].tap()
        let plugins = app.buttons["workspace.route.plugins"]
        reveal(plugins, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        plugins.tap()
        XCTAssertTrue(app.buttons["plugin.add"].waitForExistence(timeout: 5))
        app.buttons["plugin.add"].tap()
        let credential = app.secureTextFields["Bearer token (optional)"]
        XCTAssertTrue(credential.waitForExistence(timeout: 5))
        credential.tap(); credential.typeText("test-only-not-a-real-token")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(credential.waitForExistence(timeout: 5))
        XCTAssertEqual(credential.value as? String, "Bearer token (optional)")
        XCTAssertFalse(app.buttons["plugin.connect"].isEnabled)
        app.buttons["plugin.cancel"].tap()
    }

    func testPluginInstallStartsWithEmptyExplicitEndpointReviewAndCancelKeepsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("Keep plugin thought")
        app.buttons["history.open"].tap()
        let plugins = app.buttons["workspace.route.plugins"]
        reveal(plugins, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        plugins.tap()
        let add = app.buttons["plugin.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["plugin.endpoint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plugin.connect"].isEnabled)
        XCTAssertFalse(app.staticTexts["plugin.connected"].exists)
        app.buttons["plugin.cancel"].tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(input.value as? String, "Keep plugin thought")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
    }
}
