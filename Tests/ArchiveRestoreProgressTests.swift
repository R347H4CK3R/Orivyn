import XCTest
@testable import JarvisEVO

final class ArchiveRestoreProgressTests: XCTestCase {
    func testSlowConsumerRetainsOnlyLatestDisplayUpdate() async {
        let progress = ArchiveRestoreProgress()
        for n in 0..<100_000 { progress.report("progress \(n)") }
        progress.finish()
        var received: [String] = []
        for await line in progress.stream { received.append(line) }
        XCTAssertEqual(received, ["progress 99999"])
    }
    func testFinishedProgressIgnoresLateWorkerCallbacks() async {
        let progress = ArchiveRestoreProgress()
        progress.report("before")
        progress.finish()
        progress.report("stale")
        var received: [String] = []
        for await line in progress.stream { received.append(line) }
        XCTAssertEqual(received, ["before"])
    }
    func testCancelledConsumerStopsWaitingForWorker() async {
        let progress = ArchiveRestoreProgress()
        let consumer = Task { () -> String? in
            var iterator = progress.stream.makeAsyncIterator()
            return await iterator.next()
        }
        consumer.cancel()
        let result = await consumer.value
        XCTAssertNil(result)
        progress.report("late callback")
        progress.finish()
    }
    func testIndividualDisplayValuesAreBounded() async {
        let progress = ArchiveRestoreProgress()
        progress.report(String(repeating: "x", count: 100_000))
        progress.finish()
        for await line in progress.stream { XCTAssertEqual(line.count, 1000) }
    }
}
