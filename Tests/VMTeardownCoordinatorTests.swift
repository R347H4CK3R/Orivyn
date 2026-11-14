import XCTest
@testable import JarvisEVO

@MainActor
final class VMTeardownCoordinatorTests: XCTestCase {
    func testDetachWaitsForRuntimeAndCheckpointAndRepeatedStopSharesWork() async {
        let coordinator = VMTeardownCoordinator()
        var runtimeGate: CheckedContinuation<Bool, Never>?
        var checkpointGate: CheckedContinuation<Void, Never>?
        var calls = 0
        var detached = false
        let task = coordinator.stop(runtime: {
            calls += 1
            return await withCheckedContinuation { runtimeGate = $0 }
        }, checkpoint: {
            await withCheckedContinuation { checkpointGate = $0 }
        }, detach: { detached = true })
        while runtimeGate == nil { await Task.yield() }
        XCTAssertEqual(coordinator.phase, .draining)
        XCTAssertFalse(detached)
        let repeated = coordinator.stop(runtime: { XCTFail("Repeated stop must not start another owner"); return false }, checkpoint: {}, detach: { XCTFail("Repeated detach") })
        runtimeGate?.resume(returning: true)
        while checkpointGate == nil { await Task.yield() }
        XCTAssertFalse(detached)
        checkpointGate?.resume()
        let result = await task.value
        let repeatedResult = await repeated.value
        XCTAssertTrue(result)
        XCTAssertTrue(repeatedResult)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(detached)
        XCTAssertEqual(coordinator.phase, .stopped)
    }

    func testUnacknowledgedRuntimeStillDrainsButDoesNotCertifySuccessfulStop() async {
        let coordinator = VMTeardownCoordinator()
        var drained = false
        var detached = false
        let task = coordinator.stop(runtime: { false }, checkpoint: { drained = true }, detach: {
            XCTAssertTrue(drained)
            detached = true
        })
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertTrue(detached)
        XCTAssertEqual(coordinator.phase, .failed)
    }
}
