import XCTest
@testable import JarvisEVO

final class VisionDownloadProgressStateTests: XCTestCase {
    func testActiveCallbackPublishesUntilCompletionAndLateCallbackCannotReviveIt() {
        var state = VisionDownloadProgressState()
        let operation = state.begin()
        XCTAssertEqual(state.value, 0)
        state.update(0.6, for: operation)
        XCTAssertEqual(state.value, 0.6)
        state.finish(operation)
        XCTAssertNil(state.value)
        // Callback was enqueued before install returned, but executed afterward.
        state.update(1, for: operation)
        XCTAssertNil(state.value)
    }

    func testCancelInvalidatesCallbacksBeforeUnderlyingWorkHasFinished() {
        var state = VisionDownloadProgressState()
        let operation = state.begin()
        state.update(0.4, for: operation)
        state.cancel()
        // Teardown can still be suspended; old work has not reached its defer.
        state.update(0.8, for: operation)
        XCTAssertNil(state.value)
        state.finish(operation)
        XCTAssertNil(state.value)
    }

    func testOldCallbackAndCompletionCannotOverwriteNewOperation() {
        var state = VisionDownloadProgressState()
        let old = state.begin()
        state.cancel()
        let current = state.begin()
        XCTAssertNotEqual(old, current)
        state.update(0.25, for: current)
        state.update(0.99, for: old)
        XCTAssertEqual(state.value, 0.25)
        state.finish(old)
        XCTAssertEqual(state.value, 0.25)
        state.update(0.75, for: current)
        XCTAssertEqual(state.value, 0.75)
        state.finish(current)
        XCTAssertNil(state.value)
    }

    func testFreshBeginOwnsProgressEvenIfPreviousCompletionWasDelayed() {
        var state = VisionDownloadProgressState()
        let old = state.begin()
        state.update(0.9, for: old)
        let current = state.begin()
        state.update(1, for: old)
        state.finish(old)
        XCTAssertEqual(state.value, 0)
        state.update(0.1, for: current)
        XCTAssertEqual(state.value, 0.1)
    }
}
