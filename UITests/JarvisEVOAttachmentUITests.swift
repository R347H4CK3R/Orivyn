import XCTest

/// Uses the native Photos picker and a PNG seeded with simctl addmedia by CI.
/// The image is controlled test input, not an assistant response or an OCR stub.
@MainActor
final class JarvisEVOAttachmentUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        XCTAssertTrue(app.textViews["composer.input"].waitForExistence(timeout: 10))
    }

    override func tearDown() async throws {
        captureEvidence("Picker diagnostic final state")
        try await super.tearDown()
    }

    func testPhotosCancellationKeepsDraftAndAllowsFilesAfterwards() {
        let input = app.textViews["composer.input"]
        input.tap(); input.typeText("Keep the selected idea")
        app.buttons["composer.attach"].tap()
        app.buttons["attachment.photos"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        dismissPhotosPicker()
        XCTAssertEqual(input.value as? String, "Keep the selected idea")
        app.buttons["composer.attach"].tap()
        let files = app.buttons["attachment.files"]
        XCTAssertTrue(files.waitForExistence(timeout: 10))
        files.tap()
        dismissNativePicker(cancel)
        XCTAssertEqual(input.value as? String, "Keep the selected idea")
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
    }

    private func dismissPhotosPicker(file: StaticString = #filePath, line: UInt = #line) {
        // The failed runs first exposed PUPickerUnavailableView's Cancel,
        // then replaced it with the remote Photos navigation bar.
        let navigation = app.navigationBars["Photos"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 30), file: file, line: line)
        let cancel = navigation.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), file: file, line: line)
        let frame = cancel.frame
        let viewport = app.frame
        guard app.state == .runningForeground, !app.alerts.firstMatch.exists,
              !app.menus.firstMatch.exists,
              [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              frame.width >= 24, frame.height >= 24,
              navigation.frame.contains(frame), viewport.contains(frame) else {
            return XCTFail("Photos Cancel must have valid visible navigation geometry", file: file, line: line)
        }
        let geometry = XCTAttachment(string: "Photos Cancel hittable=\(cancel.isHittable), frame=\(frame), navigation=\(navigation.frame)")
        geometry.name = "Photos Cancel resolved remote geometry"
        geometry.lifetime = .keepAlways; add(geometry)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard navigation.exists, cancel.exists,
              cancel.frame.insetBy(dx: -1, dy: -1).contains(frame),
              frame.insetBy(dx: -1, dy: -1).contains(cancel.frame) else {
            return XCTFail("Photos Cancel changed after validation", file: file, line: line)
        }
        // Remote Photos elements can have valid visible frames while XCTest
        // reports them unhittable, as with the existing real photo selection.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - viewport.minX, dy: point.y - viewport.minY)).tap()
        XCTAssertTrue(navigation.waitForNonExistence(timeout: 10), "Photos must dismiss after one Cancel tap", file: file, line: line)
        XCTAssertFalse(app.buttons["Cancel"].firstMatch.exists, file: file, line: line)
    }

    private func dismissNativePicker(_ cancel: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // Existence alone can expose a moving native picker during presentation.
        // Exercise the intended control only once its public geometry settles.
        var priorFrame: CGRect?
        var stableSince: Date?
        let settled = NSPredicate { _, _ in
            guard cancel.exists, cancel.isHittable else { priorFrame = nil; stableSince = nil; return false }
            let frame = cancel.frame
            guard !frame.isEmpty else { return false }
            if priorFrame != frame { priorFrame = frame; stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince ?? Date()) >= 0.3
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: cancel)], timeout: 10),
                       .completed, "Native Cancel must be stable and hittable", file: file, line: line)
        cancel.tap()
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: cancel)], timeout: 10),
                       .completed, "Native picker must dismiss before the next app action", file: file, line: line)
    }

    func testRealPhotoImportShowsRecognizedTextAndSafeSharingChoices() {
        app.buttons["composer.attach"].tap()
        app.buttons["attachment.photos"].tap()
        // Run8's real Photos AX tree exposes the seeded asset as an Image,
        // not a Button, and uses Done to confirm its native multi-selection.
        let photo = app.images.matching(identifier: "PXGGridLayout-Info")
            .matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo,'")).firstMatch
        let foundPhoto = photo.waitForExistence(timeout: 10)
        captureEvidence("Native Photos picker before selecting the seeded fixture")
        XCTAssertTrue(foundPhoto, "The known fixture must exist in the real simulator photo library.")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(done.isEnabled, "The fixture must not already be selected before the real tap.")
        selectVisiblePhoto(photo)
        let foundDone = done.waitForExistence(timeout: 5)
        captureEvidence("Native Photos picker after selecting the seeded fixture")
        XCTAssertTrue(foundDone)
        let selectionReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [selectionReady], timeout: 5), .completed, "Photos must enable Done after real asset selection.")
        done.tap()
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment.preview.'")).firstMatch
        let imported = preview.waitForExistence(timeout: 30)
        if !imported { captureEvidence("Real Photos import failed before preview") }
        XCTAssertTrue(imported)
        preview.tap()
        captureEvidence("Real image preview before OCR and sharing assertions")
        XCTAssertTrue(app.images["attachment.image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["attachment.ocr.notice"].exists)
        XCTAssertTrue(app.staticTexts["attachment.ocr.text"].label.contains("JARVIS 42"), "This assertion uses real on-device Vision OCR.")
        XCTAssertTrue(app.buttons["attachment.share.clean"].exists)
        app.buttons["attachment.share.original"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'GPS'")).firstMatch.waitForExistence(timeout: 5))
        captureEvidence("Original photo metadata warning BEFORE outside dismissal - no sharing")
        let warning = app.sheets["Share original photo?"]
        dismissOriginalShareWarning(warning)
        let warningGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: warning)
        let popoverGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.popovers.firstMatch)
        let outsideGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.otherElements["PopoverDismissRegion"])
        let dismissed = XCTWaiter.wait(for: [warningGone, popoverGone, outsideGone], timeout: 5)
        captureEvidence("Preview after dismissing the original-share warning without sharing")
        XCTAssertEqual(dismissed, .completed, "Outside dismissal must remove the original-photo warning.")
        XCTAssertFalse(app.otherElements["PopoverDismissRegion"].exists)
        XCTAssertFalse(app.popovers.firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists, "Dismissal must not open a share activity sheet.")
        XCTAssertTrue(app.images["attachment.image"].exists)
        XCTAssertTrue(app.staticTexts["attachment.ocr.text"].label.contains("JARVIS 42"))
        XCTAssertTrue(app.buttons["attachment.share.clean"].isHittable, "A share activity must not cover the restored preview controls.")
        XCTAssertTrue(app.buttons["attachment.preview.done"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Real imported fixture image and on-device OCR"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["attachment.preview.done"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment.remove.'")).firstMatch.tap()
        XCTAssertFalse(preview.exists)
        XCTAssertTrue(app.buttons["composer.voice"].exists)
    }

    /// iOS26's observed confirmation popover omits its Cancel role button.
    /// Cancel via the actual outside-dismiss surface, never the sharing action.
    private func dismissOriginalShareWarning(_ warning: XCUIElement) {
        let popover = app.popovers.firstMatch
        let outside = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        XCTAssertTrue(outside.waitForExistence(timeout: 5))
        guard app.state == .runningForeground, !app.alerts.firstMatch.exists else {
            return XCTFail("The original-photo warning must be foreground without another alert.")
        }
        let frames = [warning.frame, popover.frame, outside.frame, app.frame]
        guard frames.allSatisfy({ frame in
            [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
                && frame.width > 0 && frame.height > 0
        }), popover.frame.contains(warning.frame) else {
            return XCTFail("The native warning/popover/dismiss region must have valid nested geometry.")
        }
        let visible = outside.frame.intersection(app.frame).insetBy(dx: 22, dy: 22)
        let top = max(visible.minY, popover.frame.maxY + 22)
        let availableHeight = visible.maxY - top
        guard !visible.isNull, visible.width >= 44, availableHeight >= 44 else {
            return XCTFail("No sufficiently large visible dismissal surface exists below this popover.")
        }
        let safeOutside = CGRect(x: visible.minX, y: top, width: visible.width, height: availableHeight)
        let point = CGPoint(x: safeOutside.midX, y: safeOutside.midY)
        let geometry = XCTAttachment(string: "Warning=\(warning.frame), full popover=\(popover.frame), dismiss region=\(outside.frame), app=\(app.frame), verified outside tap=\(point). The Share original action is never tapped.")
        geometry.name = "Original-share warning safe outside-dismiss geometry"
        geometry.lifetime = .keepAlways; add(geometry)
        // Recheck live frames immediately before the action, including the
        // complete popover/arrow rather than just the warning Sheet's bounds.
        guard warning.exists, popover.exists, outside.exists,
              outside.frame.intersection(app.frame).insetBy(dx: 22, dy: 22).contains(point),
              !popover.frame.insetBy(dx: -22, dy: -22).contains(point),
              !warning.frame.insetBy(dx: -22, dy: -22).contains(point) else {
            return XCTFail("The warning moved or its outside dismissal surface changed; no tap attempted.")
        }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY)).tap()
    }

    /// Photos is a remote view service. Its private grid-container AX identifier
    /// differs across iOS 26 runtimes; the actual photo and scroll viewport were
    /// both found on CircleCI while PXGGridLayout-Group was absent. Use their
    /// live intersection, then require Done and real OCR to prove selection.
    private func selectVisiblePhoto(_ photo: XCUIElement) {
        guard app.state == .runningForeground, !app.alerts.firstMatch.exists else {
            return XCTFail("Photos must be foreground without a blocking alert before selection.")
        }
        let scroll = app.scrollViews["photosView_content_scroll_view"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let imageFrame = photo.frame
        let frames = [imageFrame, scroll.frame, app.frame]
        guard frames.allSatisfy({ frame in
            [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
                && frame.width > 0 && frame.height > 0
        }) else { return XCTFail("Photos supplied invalid image/viewport geometry.") }
        let visible = imageFrame.intersection(scroll.frame).intersection(app.frame)
        guard !visible.isNull, visible.width >= 44, visible.height >= 44,
              visible.width * visible.height >= imageFrame.width * imageFrame.height * 0.95 else {
            return XCTFail("The thumbnail must be almost fully visible inside its actual scroll viewport before tapping.")
        }
        let point = CGPoint(x: visible.midX, y: visible.midY)
        let navigation = app.navigationBars["Photos"]
        let privacyBanner = app.otherElements["PXGSingleViewContainerView_AX"]
        guard imageFrame.insetBy(dx: 8, dy: 8).contains(point),
              !(navigation.exists && navigation.frame.contains(point)),
              !(privacyBanner.exists && privacyBanner.frame.contains(point)),
              !app.toolbars.allElementsBoundByIndex.contains(where: { $0.frame.contains(point) }) else {
            return XCTFail("The thumbnail center must be inside the image, clear of navigation, privacy banner and toolbars.")
        }
        let geometry = XCTAttachment(string: "Remote Photos Image isHittable=\(photo.isHittable), image=\(imageFrame), scroll=\(scroll.frame), app=\(app.frame), visible=\(visible), verified tap center=\(point)")
        geometry.name = "Native Photos verified visible selection geometry"
        geometry.lifetime = .keepAlways; add(geometry)
        let liveFrame = photo.frame
        guard scroll.exists, photo.exists, app.state == .runningForeground,
              !app.alerts.firstMatch.exists,
              scroll.frame.intersection(app.frame).contains(point),
              imageFrame.insetBy(dx: -1, dy: -1).contains(liveFrame),
              liveFrame.insetBy(dx: -1, dy: -1).contains(imageFrame) else {
            return XCTFail("The thumbnail moved after geometry validation; no coordinate tap was attempted.")
        }
        if photo.isHittable { photo.tap() }
        else {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY)).tap()
        }
    }

    private func captureEvidence(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " - accessibility hierarchy"
        hierarchy.lifetime = .keepAlways; add(hierarchy)
    }

}
