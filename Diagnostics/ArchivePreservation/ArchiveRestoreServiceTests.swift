import XCTest
@testable import Preservation

final class ArchiveRestoreServiceTests: XCTestCase {
    func withRoot(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "valid", withExtension: "zip", subdirectory: "Fixtures"))
        try body(root, source)
    }
    func testPreparationSurvivesServiceRecreationAndRevalidatesPlan() throws {
        try withRoot { root, source in
            let epoch = UUID()
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: epoch)
            XCTAssertEqual(review.conversationCount, 1); XCTAssertEqual(review.messageCount, 2)
            XCTAssertEqual(try ArchiveRestoreService.listReadyReviews(jobsRoot: root).map(\.jobID), [review.jobID])
            let plan = try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: root)
            XCTAssertEqual(plan.expectedEpoch, epoch); XCTAssertEqual(plan.conversations.first?.messages.count, 2)
        }
    }
    func testCorruptedPreparedPlanOrExtractedFileCannotActivate() throws {
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let job = root.appendingPathComponent(review.jobID.uuidString)
            try Data("tampered".utf8).write(to: job.appendingPathComponent("plan.json"))
            XCTAssertThrowsError(try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: root))
        }
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let job = root.appendingPathComponent(review.jobID.uuidString)
            try Data("tampered".utf8).write(to: job.appendingPathComponent("payload/extracted/conversation.txt"))
            XCTAssertThrowsError(try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: root))
        }
    }
    func testFailureRetainsPreservedOriginalWithoutReadyReview() throws {
        try withRoot { root, _ in
            let source = try XCTUnwrap(Bundle.module.url(forResource: "crc-failure", withExtension: "zip", subdirectory: "Fixtures"))
            XCTAssertThrowsError(try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID()))
            let jobs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            XCTAssertEqual(jobs.count, 1)
            guard jobs.count == 1 else { return XCTFail("Expected retained job") }
            XCTAssertTrue(FileManager.default.fileExists(atPath: jobs[0].appendingPathComponent("payload/original.zip").path))
            XCTAssertTrue(try ArchiveRestoreService.listReadyReviews(jobsRoot: root).isEmpty)
        }
    }

    func testOrphanedJobDoesNotHideHealthyPreparedReview() throws {
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            try FileManager.default.createDirectory(at: root.appendingPathComponent(UUID().uuidString), withIntermediateDirectories: false)
            XCTAssertEqual(try ArchiveRestoreService.listReadyReviews(jobsRoot: root).map(\.jobID), [review.jobID])
        }
    }
    func testMutationDuringReverificationCannotSwapReviewedPlan() throws {
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let plan = root.appendingPathComponent(review.jobID.uuidString).appendingPathComponent("plan.json")
            XCTAssertThrowsError(try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: root) { event in
                if event.hasPrefix("Reverified") {
                    let bytes = try! Data(contentsOf: plan)
                    let changed = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "Synthetic saved question", with: "Malicious swapped prompt")
                    try! Data(changed.utf8).write(to: plan)
                }
            })
        }
    }

    #if canImport(SQLite3)
    func testPreparedZIPCommitsThroughActualSQLiteAndReceiptSurvivesReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let jobs = root.appendingPathComponent("jobs")
        try FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "valid", withExtension: "zip", subdirectory: "Fixtures"))
        let databaseURL = root.appendingPathComponent("history.sqlite")
        let store = try SQLiteConversationStore(url: databaseURL)
        let epoch = try await store.textReceiveEpoch()
        let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: jobs, expectedEpoch: epoch)
        let plan = try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: jobs)
        let receipt = try await store.applyArchiveRestore(jobID: review.jobID, archiveSHA256: review.archiveSHA256,
            expectedEpoch: plan.expectedEpoch, conversations: plan.conversations)
        XCTAssertEqual(receipt.writtenConversations, 1)
        try ArchiveRestoreService.markCommitted(review: review, jobsRoot: jobs)
        XCTAssertTrue(try ArchiveRestoreService.listReadyReviews(jobsRoot: jobs).isEmpty)
        let reopened = try SQLiteConversationStore(url: databaseURL)
        let rows = try await reopened.list(includeArchived: true)
        XCTAssertEqual(rows.first?.messages.map(\.content), ["Synthetic saved question", "Synthetic saved answer"])
        let recoveredReceipt = try await reopened.archiveRestoreReceipt(jobID: review.jobID)
        XCTAssertEqual(recoveredReceipt, receipt)
    }
    func testErasureAfterPreparationPreventsArchiveResurrection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let jobs = root.appendingPathComponent("jobs")
        try FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "valid", withExtension: "zip", subdirectory: "Fixtures"))
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let epoch = try await store.textReceiveEpoch()
        let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: jobs, expectedEpoch: epoch)
        _ = try await store.deleteAll()
        let plan = try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: jobs)
        do {
            _ = try await store.applyArchiveRestore(jobID: review.jobID, archiveSHA256: review.archiveSHA256,
                expectedEpoch: plan.expectedEpoch, conversations: plan.conversations)
            XCTFail("Erased history must not return from a stale preparation")
        } catch { }
        let rows = try await store.list(includeArchived: true); XCTAssertTrue(rows.isEmpty)
    }
    #endif
}
