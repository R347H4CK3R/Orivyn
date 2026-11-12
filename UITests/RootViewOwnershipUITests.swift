import XCTest

/// Runs the actual RootView with explicitly labeled controlled view fixtures.
/// These cases do not claim hardware speech, model output, or real inference.
@MainActor
final class RootViewOwnershipUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchFixture(_ fixture: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage", "--root-view-fixture", fixture]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.notice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
    }

    func testRootSuggestionsCannotOverwriteVoiceDraftDuringPermissionListeningOrFinalizing() {
        launchFixture("voice-ownership")
        let input = app.textViews["composer.input"]
        for state in ["permission", "listening", "finishing"] {
            app.buttons["fixture.voice.\(state)"].tap()
            XCTAssertTrue(app.staticTexts["fixture.state.\(state)"].waitForExistence(timeout: 5))
            for identifier in ["suggestion.plan", "suggestion.write", "suggestion.explain"] {
                let suggestion = app.buttons[identifier]
                XCTAssertTrue(suggestion.exists)
                XCTAssertFalse(suggestion.isEnabled, "RootView must disable every suggestion while voice owns the draft.")
                // Send a real coordinate tap even though accessibility reports disabled.
                suggestion.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                XCTAssertEqual(input.value as? String, "Audio-owned draft")
            }
        }
        app.buttons["fixture.voice.stop"].tap()
        XCTAssertTrue(app.buttons["suggestion.plan"].isEnabled)
        app.buttons["suggestion.plan"].tap()
        XCTAssertEqual(input.value as? String, "Help me make a practical plan for ")
        capture("Actual RootView voice ownership fixture - not speech hardware")
    }

    func testSwitchingUnequalLongHistoriesPositionsEachAtLatestAndShortHistoryAtTop() {
        launchFixture("history-scroll")
        let transcript = app.scrollViews["conversation.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["FIXTURE A LAST"].isHittable)
        let firstRow = app.staticTexts["FIXTURE A ROW 01"]
        for _ in 0..<30 {
            if firstRow.isHittable { break }
            transcript.swipeDown()
        }
        XCTAssertTrue(firstRow.isHittable, "The old long history must be near its start, below the shorter history's maximum offset.")
        XCTAssertTrue(app.buttons["conversation.latest"].waitForExistence(timeout: 5))
        app.buttons["fixture.history.b"].tap()
        XCTAssertTrue(app.staticTexts["FIXTURE B LAST"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["FIXTURE B LAST"].isHittable, "B is shorter than A but still long; it must open at its own latest turn.")
        app.buttons["fixture.history.short"].tap()
        let short = app.staticTexts["FIXTURE SHORT TRANSCRIPT"]
        XCTAssertTrue(short.waitForExistence(timeout: 5))
        XCTAssertLessThan(short.frame.minY, app.frame.height * 0.4)
        capture("Actual RootView unequal history fixture - not inference")
    }

    func testSameConversationStreamingDoesNotPullReaderAwayFromOlderMessages() {
        launchFixture("history-scroll")
        let transcript = app.scrollViews["conversation.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        app.buttons["fixture.stream.begin"].tap()
        XCTAssertTrue(app.staticTexts["fixture.stream.waiting"].waitForExistence(timeout: 5))
        for _ in 0..<4 { transcript.swipeDown() }
        XCTAssertTrue(app.buttons["conversation.latest"].waitForExistence(timeout: 5))
        let visible = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'FIXTURE A ROW'"))
            .allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 180 && $0.frame.maxY < app.frame.height - 180 }
        guard let anchor = visible else { return XCTFail("A real older transcript row must be visible after native scroll gestures.") }
        let label = anchor.label
        let oldY = anchor.frame.minY
        app.buttons["fixture.stream.append"].tap()
        XCTAssertTrue(app.staticTexts["fixture.stream.appended"].waitForExistence(timeout: 5))
        let same = app.staticTexts[label]
        XCTAssertTrue(same.isHittable)
        XCTAssertLessThan(abs(same.frame.minY - oldY), 12, "New streamed content must not change the reader's existing position.")
        XCTAssertTrue(app.buttons["conversation.latest"].exists)
        app.buttons["conversation.latest"].tap()
        XCTAssertTrue(app.staticTexts["FIXTURE STREAM TAIL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["FIXTURE STREAM TAIL"].isHittable)
        capture("Actual RootView reading-position fixture - controlled stream, not inference")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
