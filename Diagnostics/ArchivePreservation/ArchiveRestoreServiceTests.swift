import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import Preservation

final class ArchiveRestoreServiceTests: XCTestCase {
    func withRoot(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "valid", withExtension: "zip", subdirectory: "Fixtures")).resolvingSymlinksInPath()
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
            let source = try XCTUnwrap(Bundle.module.url(forResource: "crc-failure", withExtension: "zip", subdirectory: "Fixtures")).resolvingSymlinksInPath()
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

    func testReceiptReconciliationHidesCommittedJobsDespiteMarkerFailure() async throws {
        let committed = ArchiveRestoreService.Review(jobID: UUID(), conversationCount: 1, messageCount: 1,
            unresolvedCount: 0, omittedCount: 0, retainedFileCount: 1, archiveSHA256: "committed")
        let ready = ArchiveRestoreService.Review(jobID: UUID(), conversationCount: 1, messageCount: 1,
            unresolvedCount: 0, omittedCount: 0, retainedFileCount: 1, archiveSHA256: "ready")
        let result = try await ArchiveRestoreRecovery.reconcile([committed, ready],
            isCommitted: { $0 == "committed" }, markCommitted: { _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertEqual(result.ready, [ready])
        XCTAssertEqual(result.committedJobs, [committed.jobID])
        XCTAssertEqual(result.maintenancePending, [committed.jobID])
    }
    func testReceiptLookupFailureDoesNotOfferUnknownJobForRetry() async throws {
        let review = ArchiveRestoreService.Review(jobID: UUID(), conversationCount: 1, messageCount: 1,
            unresolvedCount: 0, omittedCount: 0, retainedFileCount: 1, archiveSHA256: "unknown")
        do {
            _ = try await ArchiveRestoreRecovery.reconcile([review],
                isCommitted: { _ in throw CocoaError(.fileReadCorruptFile) },
                markCommitted: { _ in XCTFail("Unknown receipt must not update marker") })
            XCTFail("Unknown receipt state must fail closed")
        } catch { }
    }

    #if canImport(SQLite3)
    func testPreparedZIPCommitsThroughActualSQLiteAndReceiptSurvivesReopen() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let jobs = root.appendingPathComponent("jobs")
        try FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "valid", withExtension: "zip", subdirectory: "Fixtures")).resolvingSymlinksInPath()
        let databaseURL = root.appendingPathComponent("history.sqlite")
        let store = try SQLiteConversationStore(url: databaseURL)
        let epoch = try await store.textReceiveEpoch()
        let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: jobs, expectedEpoch: epoch)
        let plan = try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: jobs)
        let receipt = try await store.applyArchiveRestore(jobID: review.jobID, archiveSHA256: review.archiveSHA256,
            expectedEpoch: plan.expectedEpoch, conversations: plan.conversations)
        XCTAssertEqual(receipt.writtenConversations, 1)
        // Simulate process death after DB commit but before filesystem marking.
        let crashedReviews = try ArchiveRestoreService.listReadyReviews(jobsRoot: jobs)
        XCTAssertEqual(crashedReviews.count, 1)
        let reconciliation = try await ArchiveRestoreRecovery.reconcile(crashedReviews,
            isCommitted: { try await store.archiveRestoreReceipt(archiveSHA256: $0) != nil },
            markCommitted: { try ArchiveRestoreService.markCommitted(review: $0, jobsRoot: jobs) })
        XCTAssertTrue(reconciliation.ready.isEmpty)
        XCTAssertEqual(reconciliation.committedJobs, [review.jobID])
        XCTAssertTrue(try ArchiveRestoreService.listReadyReviews(jobsRoot: jobs).isEmpty)
        let reopened = try SQLiteConversationStore(url: databaseURL)
        let rows = try await reopened.list(includeArchived: true)
        XCTAssertEqual(rows.first?.messages.map(\.content), ["Synthetic saved question", "Synthetic saved answer"])
        let recoveredReceipt = try await reopened.archiveRestoreReceipt(jobID: review.jobID)
        XCTAssertEqual(recoveredReceipt, receipt)
    }
    func testErasureAfterPreparationPreventsArchiveResurrection() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let jobs = root.appendingPathComponent("jobs")
        try FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "valid", withExtension: "zip", subdirectory: "Fixtures")).resolvingSymlinksInPath()
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

extension ArchiveRestoreServiceTests {
    func testReadOnlyInventoryIncludesCommittedJobsWithoutChangingReadyEligibility() throws {
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            XCTAssertEqual(try ArchiveRestoreService.listInventoryReviews(jobsRoot: root), [review])
            let page = try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root)
            XCTAssertEqual(page.totalRecords, 0); XCTAssertTrue(page.entries.isEmpty)
            // A synthetic committed marker tests read-only discovery; this is not a SQLite receipt claim.
            try ArchiveRestoreService.markCommitted(review: review, jobsRoot: root)
            XCTAssertTrue(try ArchiveRestoreService.listReadyReviews(jobsRoot: root).isEmpty)
            XCTAssertEqual(try ArchiveRestoreService.listInventoryReviews(jobsRoot: root), [review])
            XCTAssertEqual(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root).totalRecords, 0)
            XCTAssertThrowsError(try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: root))
        }
    }
    func testInventoryRejectsChangedReviewStateAndPlanWithoutWriting() throws {
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let job = root.appendingPathComponent(review.jobID.uuidString)
            let stateURL = job.appendingPathComponent("state.json"), planURL = job.appendingPathComponent("plan.json")
            let state = try Data(contentsOf: stateURL), plan = try Data(contentsOf: planURL)
            var changed = review; changed.unresolvedCount += 1
            XCTAssertThrowsError(try ArchiveRestoreService.retainedInventory(review: changed, jobsRoot: root))
            XCTAssertEqual(try Data(contentsOf: stateURL), state); XCTAssertEqual(try Data(contentsOf: planURL), plan)
            try Data("tampered".utf8).write(to: planURL)
            XCTAssertThrowsError(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root))
            XCTAssertEqual(try Data(contentsOf: stateURL), state)
            try plan.write(to: planURL)
            var stateObject = try XCTUnwrap(JSONSerialization.jsonObject(with: state) as? [String: Any])
            stateObject["phase"] = "failed"
            try JSONSerialization.data(withJSONObject: stateObject).write(to: stateURL)
            XCTAssertThrowsError(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root))
            XCTAssertTrue(try ArchiveRestoreService.listInventoryReviews(jobsRoot: root).isEmpty)
        }
    }
}

extension ArchiveRestoreServiceTests {
    func testInventoryDisplaysBoundReferencesWithoutExposingOpaqueJSONAndRejectsOrphans() throws {
        try withRoot { root, source in
            var review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let job = root.appendingPathComponent(review.jobID.uuidString)
            let stateURL = job.appendingPathComponent("state.json"), planURL = job.appendingPathComponent("plan.json")
            var plan = try JSONDecoder().decode(ArchiveRestoreService.Plan.self, from: Data(contentsOf: planURL))
            let message = try XCTUnwrap(plan.conversations.first?.messages.first)
            let secret = "synthetic-private-pointer-do-not-display"
            plan.unresolved = [.init(messageID: message.id, source: "contentPart", originalJSON: Data(secret.utf8))]
            review.unresolvedCount = 1
            var state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any])
            func bindPlan() throws {
                let encoded = try JSONEncoder().encode(plan)
                try encoded.write(to: planURL)
                state["planSHA256"] = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
                state["review"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(review))
                try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
            }
            try bindPlan()
            let before = try Data(contentsOf: planURL)
            let page = try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root)
            XCTAssertEqual(page.entries.first?.id, message.id); XCTAssertEqual(page.totalRecords, 1)
            XCTAssertEqual(page.entries.first?.contentPartCount, 1)
            XCTAssertFalse(String(describing: page).contains(secret))
            XCTAssertEqual(try Data(contentsOf: planURL), before)
            plan.unresolved = [.init(messageID: UUID(), source: "contentPart", originalJSON: Data(secret.utf8))]
            try bindPlan()
            XCTAssertThrowsError(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root))
        }
    }
}

extension ArchiveRestoreServiceTests {
    func testInventoryRejectsSymlinkedPlanWithoutFollowingIt() throws {
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let job = root.appendingPathComponent(review.jobID.uuidString)
            let planURL = job.appendingPathComponent("plan.json"), other = root.appendingPathComponent("synthetic-outside-plan.json")
            let original = try Data(contentsOf: planURL)
            try original.write(to: other)
            try FileManager.default.removeItem(at: planURL)
            try FileManager.default.createSymbolicLink(at: planURL, withDestinationURL: other)
            XCTAssertThrowsError(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root))
            XCTAssertEqual(try Data(contentsOf: other), original)
        }
    }
}

extension ArchiveRestoreServiceTests {
    func testNearLimitInventoryPlanRemainsUnderHostProcessMemoryCeiling() throws {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "inventory-resource", withExtension: nil, subdirectory: "Fixtures")).resolvingSymlinksInPath()
        let reviews = try ArchiveRestoreService.listInventoryReviews(jobsRoot: root)
        XCTAssertEqual(reviews.count, 1)
        let review = try XCTUnwrap(reviews.first)
        let first = try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root)
        XCTAssertEqual(first.entries.count, 50); XCTAssertEqual(first.totalMessages, 20_000)
        XCTAssertEqual(first.totalRecords, 20_000); XCTAssertEqual(first.remaining, 19_950)
        XCTAssertEqual(first.entries.first?.id.uuidString, "00000000-0000-0000-0000-000000100001")
        XCTAssertTrue(first.entries.allSatisfy { $0.contentPartCount == 1 && $0.totalRecords == 1 })
        let last = try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root, offset: 19_950)
        XCTAssertEqual(last.entries.count, 50); XCTAssertEqual(last.remaining, 0); XCTAssertNil(last.nextOffset)
        var usage = rusage()
        #if canImport(Darwin)
        let status = getrusage(RUSAGE_SELF, &usage)
        let peakBytes = Int64(usage.ru_maxrss)
        #else
        let status = getrusage(Int32(RUSAGE_SELF.rawValue), &usage)
        let peakBytes = Int64(usage.ru_maxrss) * 1024
        #endif
        XCTAssertEqual(status, 0, "RSS measurement must succeed")
        XCTAssertGreaterThan(peakBytes, 0)
        XCTAssertLessThan(peakBytes, 256 * 1024 * 1024, "Host-process high-water includes preceding tests, not isolated inventory-only RSS")
        print("INVENTORY_RESOURCE processPeakBytes=\(peakBytes) ceilingBytes=268435456 rows=20000 page=50 metadataOnly=true")
    }
}
