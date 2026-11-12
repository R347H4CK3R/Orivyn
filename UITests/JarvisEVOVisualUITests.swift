import XCTest
import UIKit

@MainActor
final class JarvisEVOVisualUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
        // Appearance lives in standard defaults, separate from reset test storage.
        // Select it through the real settings UI so "light" evidence is deterministic.
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        let appearance = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.buttons["Light"].tap()
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 5))
    }

    // A second-row composer hides useful transcript space and puts attach/send below input.
    func testIdleComposerKeepsAllControlsOnOneRow() {
        let input = app.textViews["composer.input"].frame
        let attach = app.buttons["composer.attach"].frame
        let send = app.buttons["composer.voice"].frame
        XCTAssertLessThan(abs(input.midY - attach.midY), 14)
        XCTAssertLessThan(abs(input.midY - send.midY), 14)
        XCTAssertLessThanOrEqual(max(input.maxY, max(attach.maxY, send.maxY)) - min(input.minY, min(attach.minY, send.minY)), 66)
        assertMenuContrast(dark: false)
        capture("Reference refresh - empty light")
    }

    // A modal history sheet or a full-screen drawer violates the left-side navigation contract.
    func testHistoryIsLeftDrawerAndDismissalPreservesDraft() {
        let input = app.textViews["composer.input"]
        input.tap()
        input.typeText("Keep my draft")
        app.buttons["history.open"].tap()
        let close = app.buttons["history.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let backdrop = app.buttons["history.backdrop"]
        XCTAssertTrue(backdrop.exists)
        XCTAssertGreaterThan(backdrop.frame.minX, app.frame.width * 0.65)
        XCTAssertLessThan(backdrop.frame.width, app.frame.width * 0.3)
        capture("Reference refresh - history drawer")
        backdrop.tap()
        XCTAssertEqual(input.value as? String, "Keep my draft")
    }

    // Row swipes belong to archive/delete, not to the drawer's dismiss gesture.
    func testHistoryRowSwipeActionsDoNotDismissDrawer() {
        app.buttons["conversation.new"].tap()
        app.buttons["history.open"].tap()
        let row = app.buttons.matching(identifier: "history.conversation").firstMatch
        reveal(row, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        let backdrop = app.buttons["history.backdrop"]
        XCTAssertTrue(backdrop.exists)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "History accessibility before row swipe"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let rightEdge = row.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))
        let leftSide = row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        XCTAssertLessThanOrEqual(row.frame.maxX, backdrop.frame.minX, "The row hit target must not extend into the dismissal backdrop.")
        XCTAssertLessThan(rightEdge.screenPoint.x, backdrop.frame.minX)
        XCTAssertGreaterThanOrEqual(leftSide.screenPoint.x, row.frame.minX)
        rightEdge.press(forDuration: 0.1, thenDragTo: leftSide)
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete"].exists)
        XCTAssertTrue(app.buttons["history.close"].exists)
        app.buttons["Archive"].tap()
        app.buttons["Archived"].tap()
        reveal(row, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        app.buttons["history.close"].tap()
        XCTAssertTrue(app.textViews["composer.input"].exists)
    }

    func testSidebarSettingsReturnsToEditableComposer() {
        app.buttons["history.open"].tap()
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appearance"].waitForExistence(timeout: 5))
        capture("Reference refresh - settings")
        app.buttons["settings.done"].tap()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("A fresh thought")
        XCTAssertEqual(input.value as? String, "A fresh thought")
    }

    func testToolbarNewChatCreatesSelectableConversation() {
        app.buttons["conversation.new"].tap()
        app.buttons["history.open"].tap()
        reveal(app.buttons.matching(identifier: "history.conversation").firstMatch,
               in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        app.buttons["history.close"].tap()
        XCTAssertTrue(app.textViews["composer.input"].exists)
    }

    func testCaptureDarkAppearanceAndMultilineDraft() {
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        let appearance = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.buttons["Dark"].tap()
        app.buttons["settings.done"].tap()
        assertMenuContrast(dark: true)
        capture("Reference refresh - empty dark")
        let input = app.textViews["composer.input"]
        input.tap()
        input.typeText("Help me plan a weekend with time for a walk, a good meal, and a little reading.\nKeep the plan simple and leave some room to change my mind.")
        XCTAssertTrue(app.buttons["composer.send"].isHittable)
        XCTAssertTrue(app.buttons["composer.attach"].isHittable)
        capture("Reference refresh - multiline keyboard")
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        appearance.buttons["Light"].tap()
        app.buttons["settings.done"].tap()
    }

    // Downloads the pinned public model through the actual app, runs real inference,
    // and proves both weights/selection and the completed reply survive app relaunch.
    func testRealDownloadedModelProducesAndPersistsConversation() {
        executionTimeAllowance = 300
        let modelID = "qwen2.5-0.5b-instruct-q4_k_m"
        app.buttons["model.choose"].tap()
        let modelList = app.descendants(matching: .any).matching(identifier: "model.list").firstMatch
        let download = app.buttons["model.download.\(modelID)"]
        reveal(download, in: modelList)
        download.tap()
        XCTAssertEqual(app.state, .runningForeground, "Download must not open the neighboring model-details link.")
        XCTAssertTrue(app.buttons["model.done"].isHittable, "The Models sheet must remain interactive after starting a download.")
        let installed = app.descendants(matching: .any).matching(identifier: "model.installed.\(modelID)").firstMatch
        let catalogName = app.staticTexts["model.catalog.name.\(modelID)"]
        let installDeadline = Date().addingTimeInterval(150)
        while !installed.exists && Date() < installDeadline {
            if !catalogName.isHittable { reveal(catalogName, in: modelList, towardEnd: false) }
            _ = installed.waitForExistence(timeout: min(1, max(0.01, installDeadline.timeIntervalSinceNow)))
        }
        XCTAssertTrue(installed.exists, "The real model download or integrity verification did not finish.")
        reveal(installed, in: modelList, towardEnd: false)
        XCTAssertEqual(app.state, .runningForeground, "Installing a model must keep Orivyn in the foreground.")
        XCTAssertTrue(app.buttons["model.done"].isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Reference refresh - real model installed")
        let provider = app.buttons["model.provider.\(modelID)"]
        reveal(provider, in: modelList, towardEnd: false)
        XCTAssertTrue(provider.isEnabled)
        provider.tap()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("What is the capital of France? Answer in one short sentence.")
        app.buttons["composer.send"].tap()
        let response = app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 50), "The installed local model must produce actual reply text.")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["composer.stop"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed, "The real local response did not complete.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Response failed. Choose a model and try again."].exists)
        let text = response.label + response.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let userMessage = app.descendants(matching: .any).matching(identifier: "user.message").firstMatch
        XCTAssertLessThan(userMessage.frame.minY, app.frame.height * 0.35, "A short transcript belongs below the toolbar, not above the composer.")
        capture("Reference refresh - genuine local conversation")
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(response.waitForExistence(timeout: 10), "A completed local conversation must survive relaunch.")
        app.buttons["model.choose"].tap()
        reveal(provider, in: modelList, towardEnd: false)
        XCTAssertEqual(provider.value as? String, "Selected")
        reveal(installed, in: modelList)
        XCTAssertTrue(installed.exists)
        app.buttons["model.done"].tap()
    }

    // Measure actual screenshot pixels inside the menu artwork, not its shadow.
    // Original run6 glyph was ~80% grey in light appearance and fails this gate.
    private func assertMenuContrast(dark: Bool) {
        let screenshot = app.screenshot().image
        guard let image = screenshot.cgImage else { return XCTFail("Missing native screenshot pixels") }
        let button = app.buttons["history.open"].frame
        let sx = CGFloat(image.width) / app.frame.width
        let sy = CGFloat(image.height) / app.frame.height
        let area = CGRect(x: (button.midX - 10.5) * sx, y: (button.midY - 10.5) * sy, width: 21 * sx, height: 21 * sy).integral
        guard let crop = image.cropping(to: area) else { return XCTFail("Menu is outside the native screenshot") }
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        guard let context = CGContext(data: &pixels, width: crop.width, height: crop.height, bitsPerComponent: 8,
            bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return XCTFail("Cannot inspect menu pixels")
        }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let highContrast = stride(from: 0, to: pixels.count, by: 4).filter {
            let mean = (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3
            return dark ? mean > 184 : mean < 71
        }.count
        let fraction = Double(highContrast) / Double(crop.width * crop.height)
        let evidence = XCTAttachment(string: "Menu native pixel ROI \(area), high-contrast fraction \(fraction), appearance \(dark ? "dark" : "light")")
        evidence.name = "Menu contrast measurement"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertGreaterThan(fraction, 0.035, "Menu strokes must remain visibly high contrast inside the native toolbar.")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
