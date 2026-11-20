import XCTest

@MainActor
final class NativeToolsUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let draft = app.textViews["composer.input"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10)); draft.tap(); draft.typeText("Keep this conversation draft")
    }

    func testVisibleWebEntrySearchReviewDoesNotSendAndReturnsToSameDraft() {
        let web = app.buttons["chat.web"]
        XCTAssertTrue(web.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(web.frame.height, 44)
        XCTAssertGreaterThanOrEqual(web.frame.width, 44)
        web.tap()
        let address = app.textFields["browser.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browser.open"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Catalog04Web"; capture.lifetime = .keepAlways; add(capture)
        address.tap(); address.typeText("plumbing a & b")
        XCTAssertTrue(app.staticTexts["browser.destination"].exists)
        XCTAssertEqual(app.buttons["browser.open"].label, "Search DuckDuckGo")
        // Deliberately do not tap Go: editing must not open Safari or send a query.
        XCTAssertTrue(app.buttons["tool.review.done"].exists)
        XCTAssertFalse(app.buttons["browser.bookmark.save"].exists)
        app.buttons["tool.review.done"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Keep this conversation draft")
    }

    func testWebPassageStartsBlankAndKeepsConversationDraftSeparate() {
        let web = app.buttons["chat.web"]
        XCTAssertTrue(web.waitForExistence(timeout: 5))
        web.tap()
        let explain = app.descendants(matching: .any).matching(identifier: "browser.explain").firstMatch
        XCTAssertTrue(explain.waitForExistence(timeout: 5))
        explain.tap()
        let passage = app.textViews["passage.text"]
        XCTAssertTrue(passage.waitForExistence(timeout: 5))
        XCTAssertNotEqual(passage.value as? String, "Keep this conversation draft")
        XCTAssertFalse(app.buttons["passage.explain"].isEnabled)
        passage.tap()
        passage.typeText("Only the text I deliberately choose")
        XCTAssertTrue(app.buttons["passage.explain"].isEnabled)
        app.navigationBars.buttons["Web"].firstMatch.tap()
        app.buttons["tool.review.done"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Keep this conversation draft")
    }

    func testBookmarkFillAndRemoveAreIndependentAndNeverOpenSafari() {
        app.buttons["chat.web"].tap()
        let address = app.textFields["browser.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let saved = "https://example.com/" + UUID().uuidString
        let entered = saved + "?token=synthetic#section"
        address.tap(); address.typeText(entered)
        let list = app.collectionViews.firstMatch
        let save = app.buttons["browser.bookmark.save"]
        reveal(save, in: list); save.tap()
        let fill = app.buttons["browser.bookmark.fill." + saved]
        let remove = app.buttons["browser.bookmark.remove." + saved]
        reveal(fill, in: list)
        XCTAssertTrue(fill.isHittable); XCTAssertTrue(remove.exists)
        XCTAssertGreaterThanOrEqual(fill.frame.height, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.width, 44)
        XCTAssertFalse(fill.frame.intersects(remove.frame), "Bookmark action hit targets must not overlap")
        fill.tap()
        // A Form can scroll to its edited field and lazily unload the row.
        // Verify the actual filled value, then re-reveal the persisted bookmark.
        reveal(address, in: list, towardEnd: false)
        XCTAssertEqual(address.value as? String, saved)
        reveal(remove, in: list)
        XCTAssertTrue(remove.isHittable, "Fill must preserve the bookmark and its independent Remove action")
        reveal(address, in: list, towardEnd: false)
        address.tap(); address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: saved.count))
        address.typeText("Keep this search")
        reveal(remove, in: list); remove.tap()
        XCTAssertFalse(fill.exists)
        reveal(address, in: list, towardEnd: false)
        XCTAssertEqual(address.value as? String, "Keep this search", "Remove must not fill the address or navigate")
        XCTAssertTrue(app.buttons["tool.review.done"].exists)
        app.buttons["tool.review.done"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Keep this conversation draft")
    }

    func testCleanLinkRequiresExplicitCopyAndLeavesOriginalAddressUnchanged() {
        app.buttons["chat.web"].tap()
        let address = app.textFields["browser.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let original = "https://example.com/article?utm_source=synthetic#section"
        address.tap(); address.typeText(original)
        let list = app.collectionViews.firstMatch
        let reader = app.buttons["browser.reader"]
        reveal(reader, in: list)
        XCTAssertGreaterThanOrEqual(reader.frame.height, 44)
        let preview = app.staticTexts["browser.cleanLink.preview"]
        reveal(preview, in: list)
        XCTAssertEqual(preview.label, "https://example.com/article#section")
        XCTAssertFalse(app.staticTexts["browser.cleanLink.copied"].exists)
        let copy = app.buttons["browser.cleanLink.copy"]
        reveal(copy, in: list); copy.tap()
        XCTAssertTrue(app.staticTexts["browser.cleanLink.copied"].waitForExistence(timeout: 5))
        // This synthetic test intentionally writes only the clean example URL, never reads the clipboard.
        reveal(address, in: list, towardEnd: false)
        XCTAssertEqual(address.value as? String, original)
        XCTAssertTrue(app.buttons["tool.review.done"].exists)
        app.buttons["tool.review.done"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Keep this conversation draft")
    }

    func testMailDraftIsEditableWithoutSilentSendAndBackPreservesChat() {
        openTool("Email")
        let subject = app.textFields["mail.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5)); subject.tap(); subject.typeText("An unsent idea")
        XCTAssertTrue(app.buttons["mail.review"].exists)
        capture("Orivyn native mail draft before review")
        returnToChat()
    }

    func testCalendarUsesActualEventEditorAndCancelPreservesChat() {
        openTool("Calendar")
        let title = app.textFields["calendar.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Do not save this test event")
        app.buttons["calendar.review"].tap()
        let editor = app.navigationBars["New Event"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        let cancel = editor.buttons["cancel-button"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        capture("Orivyn actual system calendar editor")
        cancel.tap()
        let discard = app.buttons["Discard Changes"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, "Do not save this test event")
        returnToChat()
    }

    func testBrowserRejectsUnsafeSchemeThenOpensActualSafariAndReturns() {
        openTool("Browser")
        let address = app.textFields["browser.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5)); address.tap(); address.typeText("javascript:alert(1)")
        XCTAssertFalse(app.buttons["browser.open"].isEnabled)
        address.tap(); address.press(forDuration: 1)
        // Clear through the field's standard select-all keyboard action, not app internals.
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap(); address.typeText(XCUIKeyboardKey.delete.rawValue) }
        else { address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "javascript:alert(1)".count)) }
        address.typeText("https://example.com")
        XCTAssertTrue(app.buttons["browser.open"].isEnabled); app.buttons["browser.open"].tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15)); capture("Orivyn actual Safari browser"); done.tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5)); returnToChat()
    }

    func testLocationRequestsOnlyOnTapThenClearsActualSimulatorResult() {
        openTool("Location")
        let request = app.buttons["location.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["location.coordinates"].exists)
        request.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let coordinates = app.staticTexts["location.coordinates"]
        XCTAssertTrue(coordinates.waitForExistence(timeout: 35))
        XCTAssertTrue(coordinates.label.contains("37.3349"), "Use declared simulator coordinates, never a fake in-app location result.")
        capture("Orivyn actual Core Location simulator result")
        app.buttons["location.clear"].tap()
        XCTAssertTrue(coordinates.waitForNonExistence(timeout: 5)); returnToChat()
    }

    private func openTool(_ title: String) {
        app.buttons["history.open"].tap()
        let row = app.buttons["workspace.route.customize"]
        reveal(row, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        row.tap(); XCTAssertTrue(app.navigationBars["Customize"].waitForExistence(timeout: 5))
        let tool = app.staticTexts[title].firstMatch
        reveal(tool, in: app.collectionViews.firstMatch)
        tool.tap()
    }
    private func returnToChat() {
        let back = app.navigationBars.buttons["Customize"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "Keep this conversation draft")
        XCTAssertFalse(app.buttons["composer.stop"].exists)
    }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
