import XCTest
@testable import JarvisEVO

final class BackupImportConfirmationTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/synthetic/backup.json")
    func testReplacementRequiresConfirmationAndCanOnlyBeConsumedOnce() {
        var state = BackupImportConfirmation()
        XCTAssertNil(state.select(url, policy: .replaceMatching))
        XCTAssertEqual(state.pending?.url, url)
        let request = state.confirm()
        XCTAssertEqual(request?.url, url)
        XCTAssertEqual(request?.policy, .replaceMatching)
        XCTAssertNil(state.confirm())
        XCTAssertNil(state.pending)
    }
    func testCancelNeverDispatchesReplacement() {
        var state = BackupImportConfirmation()
        XCTAssertNil(state.select(url, policy: .replaceMatching))
        state.cancel()
        XCTAssertNil(state.pending)
        XCTAssertNil(state.confirm())
    }
    func testNonDestructiveModesDoNotNeedConfirmation() {
        for policy: BackupImportPolicy in [.preserveLocal, .keepBoth] {
            var state = BackupImportConfirmation()
            let request = state.select(url, policy: policy)
            XCTAssertEqual(request?.url, url)
            XCTAssertEqual(request?.policy, policy)
            XCTAssertNil(state.pending)
            XCTAssertNil(state.confirm())
        }
    }
    func testPendingSelectionCannotBeReplacedByAnotherCallback() {
        var state = BackupImportConfirmation()
        XCTAssertNil(state.select(url, policy: .replaceMatching))
        XCTAssertNil(state.select(URL(fileURLWithPath: "/different.json"), policy: .preserveLocal))
        XCTAssertEqual(state.confirm()?.url, url)
    }
    func testLatePickerResultAfterNavigationCannotRecreateReview() throws {
        var state = BackupImportConfirmation()
        let token = try XCTUnwrap(state.beginSelection(policy: .replaceMatching))
        state.invalidate()
        XCTAssertNil(state.finishSelection(token))
        XCTAssertNil(state.select(url, policy: .replaceMatching))
        XCTAssertNil(state.pending)
        XCTAssertNil(state.beginSelection(policy: .preserveLocal))
    }
    func testStalePickerDoesNotConsumeNewSelectionAfterReactivation() throws {
        var state = BackupImportConfirmation()
        let old = try XCTUnwrap(state.beginSelection(policy: .replaceMatching))
        state.invalidate()
        state.activate()
        let fresh = try XCTUnwrap(state.beginSelection(policy: .preserveLocal))
        XCTAssertNil(state.finishSelection(old))
        XCTAssertEqual(state.finishSelection(fresh), .preserveLocal)
        XCTAssertNil(state.finishSelection(fresh))
    }

    func testNewPickerSupersedesDismissedPresentationWithoutCallback() throws {
        var state = BackupImportConfirmation()
        let cancelled = try XCTUnwrap(state.beginSelection(policy: .replaceMatching))
        let next = try XCTUnwrap(state.beginSelection(policy: .keepBoth))
        XCTAssertNil(state.finishSelection(cancelled))
        XCTAssertEqual(state.finishSelection(next), .keepBoth)
    }

}
