import XCTest

@MainActor
final class ModelCatalogUITests: XCTestCase {
    func testHomeShowsChooseAIAndQuickPromptOnlyFillsDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "unavailable-provider"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        let newChat = app.buttons["conversation.new"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5)); newChat.tap()
        let choose = app.buttons["welcome.chooseAI"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(choose.frame.height, 44)
        reveal(app.buttons["suggestion.write"], in: app.scrollViews["welcome.scroll"])
        app.buttons["suggestion.write"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Help me write ")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
        app.buttons["model.choose"].tap()
        XCTAssertTrue(app.navigationBars["Choose an AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Works offline"].exists)
    }

    func testPrecisionVariantsRemainAvailableBehindDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "model-download"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        let list = app.collectionViews.firstMatch
        let options = app.descendants(matching: .any).matching(identifier: "model.variants.qwen2.5-0.5b-instruct-q4_k_m").firstMatch
        reveal(options, in: list)
        // The native failure recording shows Q5 rendered after expansion; the nested
        // name Text identifier was not reachable. Assert the actual Q5 action instead.
        let variant = app.buttons["model.download.qwen2.5-0.5b-instruct-q5_k_m"]
        let precision = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Q5_K_M")).firstMatch
        XCTAssertFalse(variant.exists, "Collapsed variants must not expose a download action")
        options.tap()
        reveal(variant, in: list)
        XCTAssertTrue(variant.isHittable)
        reveal(precision, in: list, towardEnd: false)
        XCTAssertTrue(precision.isHittable)
        // Collapse/reopen verifies disclosure state, not just a coincidental visible name.
        reveal(options, in: list, towardEnd: false)
        options.tap()
        XCTAssertTrue(variant.waitForNonExistence(timeout: 5))
        options.tap()
        reveal(variant, in: list)
        XCTAssertTrue(variant.isHittable)
        XCTAssertTrue(app.buttons["model.done"].isHittable)
    }

    func testOnlineEntryStartsWithDisclosureAndNoConnectionOrPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "unavailable-provider"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        app.buttons["model.choose"].tap()
        let online = app.buttons["freeOnline.open"]
        reveal(online, in: app.collectionViews.firstMatch)
        online.tap()
        XCTAssertTrue(app.staticTexts["freeOnline.disclosure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["freeOnline.refresh"].exists)
        XCTAssertFalse(app.secureTextFields["freeOnline.key"].exists)
        XCTAssertFalse(app.textViews["freeOnline.input"].exists)
        XCTAssertFalse(app.buttons["freeOnline.send"].exists)
        app.buttons["freeOnline.close"].tap()
        XCTAssertTrue(app.buttons["model.done"].waitForExistence(timeout: 5))
    }

    func testFilteringDoesNotHideActiveDownloadCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--root-view-fixture", "model-download"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        let search = app.textFields["model.catalog.search"]
        let list = app.collectionViews.firstMatch
        reveal(search, in: list)
        search.tap(); search.typeText("no catalog matches")
        XCTAssertTrue(app.staticTexts["No matching models. Try a different search or purpose."].waitForExistence(timeout: 5))
        let cancel = app.buttons["model.download.cancel"]
        reveal(cancel, in: list, towardEnd: false)
        XCTAssertTrue(cancel.isHittable); cancel.tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: cancel)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
