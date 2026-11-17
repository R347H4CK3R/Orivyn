import XCTest
@testable import JarvisEVO

final class ArchiveRestoreResourceTests: XCTestCase {
    func testRetainedPlanLimitsHaveActionableExplanation() {
        XCTAssertTrue(ArchiveRestoreService.Failure.limit.localizedDescription.contains("safe processing limit"))
        XCTAssertTrue(ArchiveRestoreService.Failure.limit.localizedDescription.contains("smaller export"))
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "zip"),
                      "Generate synthetic import fixtures before native tests")
    }
    func testDenseUnusedMetadataZIPPreservesOriginalAndReviewedHistory() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let jobs = root.appendingPathComponent("jobs")
        try FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture("dense-metadata"), original = try Data(contentsOf: source)
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let local = Conversation(title: "Existing local record")
        try await store.save(local)
        let epoch = try await store.textReceiveEpoch()
        let review = try await Task.detached {
            try ArchiveRestoreService.prepare(source: source, jobsRoot: jobs, expectedEpoch: epoch)
        }.value
        XCTAssertEqual(review.conversationCount, 1); XCTAssertEqual(review.messageCount, 1)
        let job = jobs.appendingPathComponent(review.jobID.uuidString)
        let stateBefore = try Data(contentsOf: job.appendingPathComponent("state.json"))
        let inventory = try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: jobs)
        XCTAssertEqual(inventory.totalRecords, 0); XCTAssertTrue(inventory.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: job.appendingPathComponent("state.json")), stateBefore)
        let before = try await store.list(includeArchived: true)
        XCTAssertEqual(before, [local], "Preparation cannot activate history")
        let plan = try await Task.detached { try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: jobs) }.value
        XCTAssertEqual(plan.conversations.first?.messages.first?.content, "Retained synthetic message")
        let receipt = try await store.applyArchiveRestore(jobID: review.jobID, archiveSHA256: review.archiveSHA256,
            expectedEpoch: plan.expectedEpoch, conversations: plan.conversations)
        XCTAssertEqual(receipt.writtenConversations, 1)
        try ArchiveRestoreService.markCommitted(review: review, jobsRoot: jobs)
        XCTAssertTrue(try ArchiveRestoreService.listReadyReviews(jobsRoot: jobs).isEmpty)
        XCTAssertEqual(try ArchiveRestoreService.listInventoryReviews(jobsRoot: jobs), [review])
        XCTAssertEqual(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: jobs).totalRecords, 0)
        let retained = try await store.load(id: local.id)
        XCTAssertEqual(retained, local)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let preserved = jobs.appendingPathComponent(review.jobID.uuidString).appendingPathComponent("payload/original.zip")
        XCTAssertEqual(try Data(contentsOf: preserved), original)
    }
    func testRetainedInventoryRejectsMismatchedReviewAndChangedPlan() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let review = try ArchiveRestoreService.prepare(source: fixture("dense-metadata"), jobsRoot: root, expectedEpoch: UUID())
        var changed = review; changed.messageCount += 1
        XCTAssertThrowsError(try ArchiveRestoreService.retainedInventory(review: changed, jobsRoot: root))
        let plan = root.appendingPathComponent(review.jobID.uuidString).appendingPathComponent("plan.json")
        let original = try Data(contentsOf: plan)
        var tampered = original; tampered.append(32); try tampered.write(to: plan)
        XCTAssertThrowsError(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root))
        XCTAssertEqual(try Data(contentsOf: plan), tampered, "Read-only rejection must not rewrite retained evidence")
    }
    func testMalformedUnknownMetadataRetainsOriginalWithoutReadyPlan() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture("malformed-metadata"), original = try Data(contentsOf: source)
        do {
            _ = try await Task.detached { try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID()) }.value
            XCTFail("Malformed skipped metadata must invalidate whole preparation")
        } catch { }
        let report = try ArchiveRestoreService.inspectRetainedJobs(jobsRoot: root)
        XCTAssertTrue(report.reviews.isEmpty); XCTAssertEqual(report.incompleteJobs.count, 1)
        let preserved = root.appendingPathComponent(try XCTUnwrap(report.incompleteJobs.first).uuidString).appendingPathComponent("payload/original.zip")
        XCTAssertEqual(try Data(contentsOf: preserved), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
