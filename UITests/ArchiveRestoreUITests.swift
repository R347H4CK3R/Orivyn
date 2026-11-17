import XCTest

@MainActor
final class ArchiveRestoreUITests: XCTestCase {
    private let title = "Synthetic ZIP Restore Acceptance"

    func testRealZIPPickerCancelsAndReopensWithoutRestore() {
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app)
        for attempt in 1...2 {
            chooseZIP(app)
            let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
            let cancel = navigation.buttons["Cancel"]
            for _ in 0..<6 where !cancel.exists {
                let back = navigation.buttons["BackButton"]
                guard back.exists else { break }
                back.tap()
            }
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
            screenshot(app, "Actual ZIP picker before cancellation \(attempt)")
            cancel.tap()
            waitAbsent(navigation)
            XCTAssertTrue(app.buttons["archive.choose-zip"].isEnabled)
            XCTAssertFalse(app.buttons["archive.confirm"].exists)
        }
        relaunch(app)
        assertHistoryAbsent(app)
    }

    func testActualZIPSelectionReviewCommitAndRelaunchHistory() {
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app)
        selectFixtureZIP(app)
        assertReview(app)
        commitPrepared(app)
        relaunch(app)
        assertRestoredHistory(app)
    }

    func testPreparedZIPSurvivesRelaunchButDoesNotActivateUntilConfirmed() {
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app)
        selectFixtureZIP(app)
        assertReview(app)
        relaunch(app)
        assertHistoryAbsent(app)
        openRestore(app)
        let refresh = app.buttons["archive.refresh-retained"]
        reveal(refresh, in: app.collectionViews.firstMatch)
        refresh.tap()
        let retained = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Review 1 conversations")).firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout: 30), app.debugDescription)
        reveal(retained, in: app.collectionViews.firstMatch)
        retained.tap()
        assertReview(app)
        screenshot(app, "Retained ZIP preparation reviewed after relaunch")
        commitPrepared(app)
        relaunch(app)
        assertRestoredHistory(app)
    }

    func testRetainedMediaInventoryRemainsReadOnlyAfterCommitAndRelaunch() {
        executionTimeAllowance = 240 // Includes two explicit read-only format inspections.
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app); selectFixtureZIP(app); assertReview(app)
        tapUnobscured(app.buttons["archive.inspect-format"], in: app, towardEnd: false)
        assertFormatReport(app)
        reveal(app.buttons["archive.confirm"], in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(app.buttons["archive.confirm"].exists, "Format report must not commit history")
        tapUnobscured(app.buttons["archive.close-format"], in: app)
        let inspect = app.buttons["archive.inspect-media"]
        tapUnobscured(inspect, in: app, towardEnd: false)
        assertInventoryLoaded(app)
        let summary = app.staticTexts["archive.media-summary"]
        reveal(summary, in: app.collectionViews.firstMatch)
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 retained reference records")).firstMatch.exists)
        screenshot(app, "Retained media inventory before restore")
        reveal(app.buttons["archive.confirm"], in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(app.buttons["archive.confirm"].exists, "Inventory must not commit history")
        commitPrepared(app); relaunch(app); openRestore(app)
        let refresh = app.buttons["archive.refresh-media"]
        tapUnobscured(refresh, in: app)
        let retained = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Inspect retained media")).firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout: 30))
        tapUnobscured(retained, in: app)
        assertInventoryLoaded(app)
        reveal(summary, in: app.collectionViews.firstMatch)
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["archive.confirm"].exists, "Committed inventory must not become a restore proposal")
        screenshot(app, "Retained media inventory after relaunch")
        tapUnobscured(app.buttons["archive.retained-format"], in: app, towardEnd: false)
        assertFormatReport(app)
        XCTAssertFalse(app.buttons["archive.confirm"].exists, "Format report must not create a restore proposal")
    }

    func testManualAttachmentRequiresConfirmationAndSurvivesRelaunchWithoutReplayDuplication() {
        executionTimeAllowance = 600 // Prior exact flow took 472.6s; DAT and added report rows expand navigation.
        continueAfterFailure = false
        let app = launchFresh()
        openRestore(app); selectFixtureZIP(app); assertReview(app); commitPrepared(app)
        relaunch(app); assertRestoredHistory(app)
        let preview = app.buttons["Preview reviewed-note.dat"]
        XCTAssertFalse(preview.exists, "Text restoration alone must not activate an attachment")

        openRestore(app); reviewManualAttachment(app)
        tapUnobscured(app.buttons["archive.attach-cancel"], in: app)
        waitAbsent(app.buttons["archive.attach-confirm"])
        relaunch(app); assertRestoredHistory(app)
        XCTAssertFalse(preview.exists, "Cancelling per-file review must leave history without the attachment")

        openRestore(app); reviewManualAttachment(app)
        tapUnobscured(app.buttons["archive.attach-confirm"], in: app)
        waitArchiveStatus("Reviewed attachment saved. Original archive and unlinked reference records are unchanged; other media is not claimed as restored.", app)
        screenshot(app, "One explicitly reviewed attachment committed")
        relaunch(app); assertRestoredHistory(app)
        XCTAssertTrue(preview.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Preview reviewed-note.dat")).count, 1)
        preview.tap()
        XCTAssertTrue(app.buttons["attachment.preview.done"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.navigationBars["reviewed-note.dat"].exists, app.debugDescription)
        XCTAssertTrue(app.otherElements["attachment.document.preview"].waitForExistence(timeout: 15), "Must show the real local-file QuickLook view, not an extracted-text fallback")
        screenshot(app, "Actual retained attachment preview after relaunch")
        attachHierarchy(app, "Retained attachment preview after relaunch")
        app.buttons["attachment.preview.done"].tap()

        // A repeated explicit request returns the saved receipt, not another copy.
        openRestore(app); reviewManualAttachment(app)
        tapUnobscured(app.buttons["archive.attach-confirm"], in: app)
        waitArchiveStatus("This source already has a saved attachment receipt. No file was copied or attached again, including if you removed it later.", app)
        relaunch(app); assertRestoredHistory(app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Preview reviewed-note.dat")).count, 1)
    }
    private func assertFormatReport(_ app: XCUIApplication) {
        waitArchiveStatus("Local format report loaded. No files were attached and nothing was sent.", app)
        let summary = app.staticTexts["archive.format-summary"]
        reveal(summary, in: app.collectionViews.firstMatch)
        XCTAssertEqual(summary.label, "Retained files: 5 · DAT files: 1 · supported-extension files: 3 · other files: 1")
        let limits = app.staticTexts["archive.format-limitations"]
        reveal(limits, in: app.collectionViews.firstMatch)
        XCTAssertTrue(limits.label.contains("Metadata presence is not format validation or an automatic attachment mapping."))
        XCTAssertFalse(app.buttons["archive.attach-confirm"].exists)
        screenshot(app, "Read-only local format report")
    }
    private func reviewManualAttachment(_ app: XCUIApplication) {
        tapUnobscured(app.buttons["archive.refresh-media"], in: app)
        let find = app.buttons["archive.find-retained-attachments"]
        XCTAssertTrue(find.waitForExistence(timeout: 30), app.debugDescription)
        tapUnobscured(find, in: app)
        waitArchiveStatus("Retained files loaded. Choose one file and then its destination message.", app)
        XCTAssertFalse(app.buttons["archive.attach-confirm"].exists, "No automatic target or pending confirmation")
        let file = app.buttons.matching(identifier: "archive.attachment-file").matching(NSPredicate(format: "label CONTAINS %@", "assets/reviewed-note.dat")).firstMatch
        tapUnobscured(file, in: app)
        waitArchiveStatus("Visible messages loaded. Choose the destination yourself. No file was attached.", app)
        XCTAssertFalse(app.buttons["archive.attach-confirm"].exists, "Choosing a file does not choose a message")
        let target = app.buttons.matching(identifier: "archive.attachment-target").matching(NSPredicate(format: "label CONTAINS %@", "Synthetic ZIP acceptance question.")).firstMatch
        tapUnobscured(target, in: app)
        waitArchiveStatus("Attachment ready for explicit confirmation. No file was attached.", app)
        reveal(app.staticTexts["archive.attachment-message"], in: app.collectionViews.firstMatch)
        XCTAssertEqual(app.staticTexts["archive.attachment-message"].label, "Synthetic ZIP acceptance question.")
        reveal(app.buttons["archive.attach-confirm"], in: app.collectionViews.firstMatch)
        XCTAssertTrue(app.buttons["archive.attach-confirm"].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
    }
    private func waitArchiveStatus(_ expected: String, _ app: XCUIApplication) {
        let status = app.staticTexts["archive.status"]
        reveal(status, in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: status)], timeout: 45), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
    }

    /// XCTest can call a row under iOS's translucent navigation bar hittable.
    /// Require its full frame inside the unobscured List viewport before tapping.
    private func tapUnobscured(_ target: XCUIElement, in app: XCUIApplication,
                               towardEnd: Bool = true) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let navigation = app.navigationBars.firstMatch
        for _ in 0..<12 {
            let top = max(list.frame.minY, navigation.exists ? navigation.frame.maxY : list.frame.minY) + 12
            let bottom = list.frame.maxY - 12
            var down = towardEnd
            if target.exists && !target.frame.isEmpty {
                if target.frame.minY > top && target.frame.maxY < bottom && target.isHittable && target.isEnabled {
                    attachHierarchy(app, "Unobscured inventory control before tap")
                    screenshot(app, "Unobscured inventory control before tap")
                    target.tap()
                    return
                }
                if target.frame.minY <= top { down = false }
                else if target.frame.maxY >= bottom { down = true }
            }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.65 : 0.4))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.4 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Inventory control must be enabled and inside the unobscured viewport. " + app.debugDescription)
    }
    private func assertInventoryLoaded(_ app: XCUIApplication) {
        let status = app.staticTexts["archive.status"]
        reveal(status, in: app.collectionViews.firstMatch, towardEnd: false)
        let loaded = NSPredicate(format: "label == %@", "Read-only inventory loaded. No media was linked or activated.")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: status)], timeout: 30), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
        attachHierarchy(app, "Verified read-only inventory loaded")
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func openRestore(_ app: XCUIApplication) {
        app.buttons["toolbar.more"].tap()
        app.buttons["settings.open"].tap()
        let link = app.buttons["settings.import-chatgpt-zip"]
        reveal(link, in: app.collectionViews.firstMatch)
        XCTAssertTrue(link.isEnabled)
        link.tap()
        XCTAssertTrue(app.buttons["archive.choose-zip"].waitForExistence(timeout: 10))
    }
    private func chooseZIP(_ app: XCUIApplication) {
        let choose = app.buttons["archive.choose-zip"]
        reveal(choose, in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(choose.isEnabled)
        choose.tap()
        XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func selectFixtureZIP(_ app: XCUIApplication) {
        chooseZIP(app)
        let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        let tabs = app.tabBars["DOC.browsingModeTabBar"]
        let browse = tabs.buttons["Browse"]
        let sidebar = app.collectionViews["Browse View"]
        let phone = app.cells["DOC.sidebar.item.On My iPhone"]
        let locations = app.cells["DOC.sidebar.header.Locations"]
        let tags = app.cells["DOC.sidebar.header.Tags"]
        let folder = app.cells.containing(.staticText, identifier: "Archive Fixture").firstMatch
        let file = app.cells.containing(.staticText, identifier: "Synthetic ChatGPT Backup.zip").firstMatch
        // One bounded navigation attempt, not a repeated picker/test retry. Slow
        // provider presentation was observed in failure recordings. Share a 60s
        // budget across state waits so the longer restore assertions still run.
        let deadline = Date().addingTimeInterval(60)
        func ready(_ item: XCUIElement) -> Bool { item.exists && item.isEnabled && item.isHittable }
        func presented() -> Bool {
            navigation.exists && !navigation.frame.isEmpty &&
                app.frame.contains(navigation.frame) && navigation.frame.minY < app.frame.midY
        }
        func contentReady() -> Bool { ready(file) || ready(folder) || ready(phone) || ready(locations) || ready(tags) }
        func navigationState() -> [String] {
            let back = navigation.buttons["BackButton"]
            return navigation.staticTexts.allElementsBoundByIndex.map(\.label) + [back.exists ? back.label : "<no back control>"]
        }
        guard waitFilesState("Fully presented Files content", app, deadline: deadline, condition: {
            presented() && (contentReady() || (tabs.exists && ready(browse)))
        }) else { return }
        if !ready(file) && !ready(folder) {
            if tabs.exists && ready(browse) && !browse.isSelected {
                recordFilesState(app, "Before selecting Files Browse tab")
                browse.tap()
                guard waitFilesState("Files Browse tab selected", app, deadline: deadline, condition: {
                    presented() && browse.isSelected && (contentReady() || navigation.buttons["BackButton"].exists)
                }) else { return }
                recordFilesState(app, "After selecting Files Browse tab")
            }
            // If Files restored a nested directory, follow only its own Back
            // control, checking a concrete changed navigation state each time.
            for step in 0..<6 {
                if ready(file) || ready(folder) || phone.exists || locations.exists || tags.exists { break }
                let back = navigation.buttons["BackButton"]
                guard ready(back) else { break }
                let previous = navigationState()
                recordFilesState(app, "Before Files Back transition \(step)")
                back.tap()
                guard waitFilesState("Changed Files Back state", app, deadline: deadline, condition: {
                    presented() && (contentReady() ||
                        navigationState() != previous)
                }) else { return }
                recordFilesState(app, "After Files Back transition \(step)")
            }
            if !ready(file) && !ready(folder) {
                // Only reveal an observed offscreen location in the actual Files
                // sidebar. Tags-only at the top is not proof of collapsed Locations.
                if phone.exists && !phone.isHittable && sidebar.exists {
                    for step in 0..<3 where !ready(phone) {
                        guard phone.frame.minY < navigation.frame.maxY else { break }
                        recordFilesState(app, "Before Files sidebar reveal \(step)")
                        sidebar.swipeDown()
                        recordFilesState(app, "After Files sidebar reveal \(step)")
                    }
                }
                guard waitFilesState("Files On My iPhone location ready", app, deadline: deadline, condition: {
                    presented() && ready(phone)
                }) else { return }
                recordFilesState(app, "Before exact Files On My iPhone cell")
                phone.tap()
                // A Selected sidebar row is not directory navigation success.
                guard waitFilesState("On My iPhone folder content", app, deadline: deadline, condition: {
                    presented() && (ready(folder) || ready(file))
                }) else { return }
                recordFilesState(app, "After On My iPhone content transition")
            }
        }
        if !ready(file) {
            XCTAssertTrue(ready(folder), "Exact fixture folder must be selectable: \(app.debugDescription)")
            guard ready(folder) else { return }
            recordFilesState(app, "Before exact Archive Fixture folder cell")
            folder.tap()
            guard waitFilesState("Archive Fixture ZIP content", app, deadline: deadline, condition: {
                presented() && ready(file)
            }) else { return }
            recordFilesState(app, "After Archive Fixture content transition")
        }
        // Real selectable document tile; no URL or selected-document injection.
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(file.isEnabled, "Synthetic ZIP tile must be selectable: \(app.debugDescription)")
        XCTAssertTrue(file.isHittable, "Synthetic ZIP tile must be visible: \(app.debugDescription)")
        recordFilesState(app, "Files ZIP tile before selection")
        file.tap()
        recordFilesState(app, "Files ZIP tile after selection")
        waitAbsent(navigation, timeout: 15)
    }
    private func recordFilesState(_ app: XCUIApplication, _ name: String) {
        attachHierarchy(app, name)
        screenshot(app, name)
    }
    private func waitFilesState(_ name: String, _ app: XCUIApplication, deadline: Date,
                                condition: @escaping () -> Bool) -> Bool {
        let timeout = min(30, max(0, deadline.timeIntervalSinceNow))
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: timeout)
        guard result == .completed else {
            recordFilesState(app, "Failed Files state: " + name)
            XCTFail("Files did not reach expected state: \(name). \(app.debugDescription)")
            return false
        }
        return true
    }
    private func assertReview(_ app: XCUIApplication) {
        let confirm = app.buttons["archive.confirm"]
        let counts = app.staticTexts["1 conversations · 2 messages"]
        reveal(counts, in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(counts.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(counts.exists, app.debugDescription)
        let unresolved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 retained unlinked reference records")).firstMatch
        XCTAssertTrue(unresolved.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
        // Extra truthful disclosures can move the confirmation row below the
        // lazy List viewport. Reveal it; do not equate offscreen with missing.
        reveal(confirm, in: app.collectionViews.firstMatch)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        screenshot(app, "Actual ZIP review before explicit commit")
    }
    private func commitPrepared(_ app: XCUIApplication) {
        let confirm = app.buttons["archive.confirm"]
        reveal(confirm, in: app.collectionViews.firstMatch)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        waitAbsent(confirm, timeout: 60)
        let status = app.staticTexts["archive.status"]
        reveal(status, in: app.collectionViews.firstMatch, towardEnd: false)
        XCTAssertTrue(status.label.contains("Restore receipt verified: 1 added"), app.debugDescription)
        XCTAssertFalse(app.staticTexts["archive.error"].exists, app.debugDescription)
        screenshot(app, "Committed ZIP restore receipt")
    }
    private func assertHistoryAbsent(_ app: XCUIApplication) {
        app.buttons["history.open"].tap()
        let rows = app.buttons.matching(identifier: "history.conversation").matching(NSPredicate(format: "label == %@", title))
        XCTAssertEqual(rows.count, 0, "Preparation or cancellation must not activate history")
        app.buttons["history.close"].tap()
    }
    private func assertRestoredHistory(_ app: XCUIApplication) {
        app.buttons["history.open"].tap()
        let rows = app.buttons.matching(identifier: "history.conversation").matching(NSPredicate(format: "label == %@", title))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(rows.count, 1, "The restored conversation must not be duplicated")
        reveal(rows.firstMatch, in: app.descendants(matching: .any).matching(identifier: "history.list").firstMatch)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic ZIP acceptance question."].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Synthetic ZIP acceptance answer."].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.textViews["composer.input"].isEnabled)
        screenshot(app, "Restored conversation messages after relaunch")
    }
    private func waitAbsent(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let absent = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: absent, object: element)], timeout: timeout), .completed)
    }
    private func attachHierarchy(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
