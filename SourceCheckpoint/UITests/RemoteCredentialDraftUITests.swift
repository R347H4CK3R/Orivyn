import XCTest

/// Future native gate: not a host verification of scene lifecycle or Keychain.
@MainActor final class RemoteCredentialDraftUITests: XCTestCase {
    func testTypedDraftIsClearedWhenAppLeavesForeground() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        app.buttons["toolbar.more"].tap(); app.buttons["settings.open"].tap()
        let link = app.buttons["Your remote endpoint"]
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        let field = app.secureTextFields["remote.key"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("synthetic-draft-not-a-credential")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == "Replacement API key (optional)", "An unsaved draft must not remain after returning to foreground.")
    }
}
