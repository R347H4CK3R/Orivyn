import XCTest

@MainActor
final class OrivynWorkspaceUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
    }
    func testSidebarAndCodingEntryPreserveDraft() {
        let input = app.textViews["composer.input"]
        input.tap(); input.typeText("Keep my unsent text")
        route("studio"); app.buttons["Start coding conversation"].tap()
        XCTAssertEqual(input.value as? String, "Keep my unsent text")
        for section in ["space", "images", "plugins", "scheduled", "customize", "sites"] {
            route(section); route("chat")
            XCTAssertEqual(input.value as? String, "Keep my unsent text")
        }
    }
    func testSpaceDocumentsFilterCannotHideImagesRoute() {
        route("space")
        let documents = app.buttons["workspace.filter.Documents"]
        XCTAssertTrue(documents.waitForExistence(timeout: 5)); documents.tap(); XCTAssertTrue(documents.isSelected)
        route("images")
        let all = app.buttons["workspace.filter.All"]
        XCTAssertTrue(all.waitForExistence(timeout: 5)); XCTAssertTrue(all.isSelected)
        XCTAssertFalse(app.buttons["workspace.filter.Documents"].exists)
    }
    func testProjectCreationSurvivesRelaunch() {
        route("projects"); app.buttons["workspace.project.new"].tap()
        let alert = app.alerts["New project"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields["Project name"].tap(); alert.textFields["Project name"].typeText("Trip planning")
        alert.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Trip planning"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10)); route("projects")
        XCTAssertTrue(app.staticTexts["Trip planning"].waitForExistence(timeout: 5))
    }
    func testNoFakeAccountsOrScheduledExecution() {
        route("plugins")
        XCTAssertTrue(app.staticTexts["No external integrations connected"].waitForExistence(timeout: 5))
        route("scheduled")
        XCTAssertTrue(app.staticTexts["Scheduled actions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["New task"].exists)
    }
    private func route(_ section: String) {
        let opener = app.buttons["history.open"].exists ? app.buttons["history.open"] : app.buttons["workspace.menu"]
        XCTAssertTrue(opener.waitForExistence(timeout: 5)); opener.tap()
        let target = app.buttons["workspace.route.\(section)"]
        reveal(target, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        target.tap()
    }
}
