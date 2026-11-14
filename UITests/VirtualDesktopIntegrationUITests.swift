import XCTest

@MainActor
final class VirtualDesktopIntegrationUITests: XCTestCase {
    func testActualGuestFileAndCheckpointThenSafeClosePreservesDraft() {
        // Guest startup (150s), command (40s), and checkpoint (60s) each have
        // their own bounds; the default 120s cannot cover this complete flow.
        executionTimeAllowance = 600
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let composer = app.textViews["composer.input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap(); composer.typeText("Keep this desktop task")
        app.buttons["history.open"].tap()
        let customize = app.buttons["workspace.route.customize"]
        reveal(customize, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        customize.tap()
        let devices = app.staticTexts["Devices"].firstMatch
        reveal(devices, in: app.collectionViews.firstMatch); devices.tap()
        let desktop = app.buttons["desktop.open"]
        XCTAssertTrue(desktop.waitForExistence(timeout: 5)); desktop.tap()
        revealDesktopControl(app.buttons["Live diagnostics"], in: app)
        app.buttons["Live diagnostics"].tap()
        let surface = app.descendants(matching: .any).matching(identifier: "desktop.surface").firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(surface.frame.height, 140, "Diagnostics must not collapse the guest viewport")
        let console = app.staticTexts["desktop.console"]
        let ready = NSPredicate(format: "label CONTAINS %@", "ORIVYN_DESKTOP_SHELL_READY_v1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: console)], timeout: 150), .completed)
        let input = app.textFields["desktop.input"]
        // Exercise compact height with diagnostics expanded, then while typing.
        // Always restore orientation so subsequent tests do not inherit it.
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 10), .completed, "Rotation must actually produce compact landscape geometry")
        revealDesktopControl(input, in: app)
        input.tap(); input.typeText("landscape draft")
        XCTAssertGreaterThanOrEqual(surface.frame.height, 180, "Landscape keyboard must scroll, not crush guest pixels")
        let hide = app.buttons["desktop.keyboard.hide"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        XCTAssertEqual(input.value as? String, "landscape draft")
        revealDesktopControl(input, in: app)
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "landscape draft".count))
        hide.tap()
        revealDesktopControl(app.buttons["desktop.checkpoint.save"], in: app)
        XCTAssertTrue(app.buttons["desktop.checkpoint.save"].isHittable)
        XCUIDevice.shared.orientation = .portrait
        revealDesktopControl(input, in: app)
        input.tap(); input.typeText("echo APP_GUEST_319 > /tmp/home/app.txt; cat /tmp/home/app.txt > /dev/ttyS0")
        XCTAssertGreaterThanOrEqual(surface.frame.height, 120, "Typing with diagnostics open must not collapse the guest viewport")
        app.buttons["desktop.input.send"].tap()
        let keyboardHidden = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardHidden, object: app.keyboards.firstMatch)], timeout: 5), .completed)
        XCTAssertGreaterThanOrEqual(surface.frame.height, 140, "Sending must leave a usable guest viewport")
        let wrote = NSPredicate(format: "label CONTAINS %@", "APP_GUEST_319")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: wrote, object: console)], timeout: 40), .completed)
        revealDesktopControl(app.buttons["desktop.checkpoint.save"], in: app)
        app.buttons["desktop.checkpoint.save"].tap()
        let saved = NSPredicate(format: "label CONTAINS %@", "Checkpoint verified and saved")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: app.staticTexts["desktop.checkpoint.status"])], timeout: 60), .completed)
        revealDesktopControl(surface, in: app)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Production guest file and saved checkpoint"; image.lifetime = .keepAlways; add(image)
        app.buttons["desktop.close"].tap()
        XCTAssertTrue(app.buttons["desktop.open"].waitForExistence(timeout: 30))
        app.navigationBars.buttons["Customize"].firstMatch.tap()
        app.buttons["workspace.menu"].tap(); app.buttons["workspace.route.chat"].tap()
        XCTAssertEqual(composer.value as? String, "Keep this desktop task")
    }
    /// Separate acceptance gate: persisted guest RAM must survive app destruction.
    /// A fresh read challenge prevents the write command or old console text from
    /// being mistaken for restored file content. Requires actual Apple UI execution.
    func testCheckpointSurvivesAppRelaunchAndFreshGuestRead() {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let app = XCUIApplication()
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let challenge = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let file = "/tmp/home/orivyn-\(value).txt"
        let expected = "RESTORED_\(challenge):\(value)"

        func openDesktop() {
            XCTAssertTrue(app.buttons["history.open"].waitForExistence(timeout: 10))
            app.buttons["history.open"].tap()
            let customize = app.buttons["workspace.route.customize"]
            reveal(customize, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
            customize.tap()
            let devices = app.staticTexts["Devices"].firstMatch
            reveal(devices, in: app.collectionViews.firstMatch); devices.tap()
            let desktop = app.buttons["desktop.open"]
            XCTAssertTrue(desktop.waitForExistence(timeout: 5)); desktop.tap()
            revealDesktopControl(app.buttons["Live diagnostics"], in: app)
        app.buttons["Live diagnostics"].tap()
            let ready = NSPredicate(format: "label CONTAINS %@", "ORIVYN_DESKTOP_SHELL_READY_v1")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app.staticTexts["desktop.console"])], timeout: 150), .completed)
        }
        func send(_ command: String) {
            let input = app.textFields["desktop.input"]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            revealDesktopControl(input, in: app)
        input.tap(); input.typeText(command)
            let button = app.buttons["desktop.input.send"]
            let enabled = NSPredicate(format: "enabled == true")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: button)], timeout: 10), .completed)
            button.tap()
        }
        func waitForStatus(_ text: String) {
            let predicate = NSPredicate(format: "label CONTAINS %@", text)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["desktop.checkpoint.status"])], timeout: 60), .completed)
        }

        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch(); openDesktop()
        send("printf '%s' '\(value)' > \(file); sync; printf 'WRITE_%s\\n' '\(value)' > /dev/ttyS0")
        let written = NSPredicate(format: "label CONTAINS %@", "WRITE_\(value)")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: written, object: app.staticTexts["desktop.console"])], timeout: 40), .completed)
        revealDesktopControl(app.buttons["desktop.checkpoint.save"], in: app)
        app.buttons["desktop.checkpoint.save"].tap()
        waitForStatus("Checkpoint verified and saved")
        app.terminate()

        // Crucially do not reset storage on the second launch.
        app.launchArguments = ["--uitesting"]
        app.launch(); openDesktop()
        XCTAssertFalse(app.staticTexts["desktop.console"].label.contains(expected))
        revealDesktopControl(app.buttons["Restore"], in: app)
        app.buttons["Restore"].tap()
        waitForStatus("Checkpoint verified and restored")
        XCTAssertFalse(app.buttons["desktop.input.send"].isEnabled)
        XCTAssertTrue(app.buttons["Resume"].isEnabled)
        app.buttons["Resume"].tap()
        send("printf 'RESTORED_%s:%s\\n' '\(challenge)' \"$(cat \(file))\" > /dev/ttyS0")
        let restored = NSPredicate(format: "label CONTAINS %@", expected)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: app.staticTexts["desktop.console"])], timeout: 40), .completed)
        // The successful fresh guest read proves Resume ran. The historical
        // checkpoint result must no longer instruct Resume or claim a paused CPU.
        XCTAssertFalse(app.buttons["Resume"].isEnabled)
        XCTAssertEqual(app.staticTexts["desktop.checkpoint.status"].label, "Checkpoint verified and restored.")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Fresh guest file read after app relaunch and checkpoint restore"
        evidence.lifetime = .keepAlways; add(evidence)
        app.buttons["desktop.close"].tap()
        XCTAssertTrue(app.buttons["desktop.open"].waitForExistence(timeout: 30))
    }
    private func revealDesktopControl(_ element: XCUIElement, in app: XCUIApplication) {
        let controls = app.scrollViews["desktop.controls"]
        if element.isHittable { return }
        for _ in 0..<4 {
            controls.swipeDown()
            if element.isHittable { return }
        }
        for _ in 0..<8 {
            controls.swipeUp()
            if element.isHittable { return }
        }
        XCTAssertTrue(element.isHittable, "Desktop control must remain reachable")
    }

}
