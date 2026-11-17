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
    func testCancelledDATStagingDoesNotCreateOwnedCopyOrChangeOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "dat-assets", withExtension: "zip", subdirectory: "Fixtures")).resolvingSymlinksInPath()
        let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
        let file = try XCTUnwrap(ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root).items.first { $0.relativePath == "assets/text.dat" })
        let message = try XCTUnwrap(ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root).items.first)
        let candidate = try ArchiveRestoreService.manualAttachmentCandidate(review: review, jobsRoot: root, file: file, message: message)
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try ArchiveRestoreService.stageAttachment(candidate: candidate, review: review, jobsRoot: root); return false }
            catch is CancellationError { return true }
            catch { return false }
        }.value
        XCTAssertTrue(cancelled)
        let job = root.appendingPathComponent(review.jobID.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: job.appendingPathComponent("attachment-staging").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.appendingPathComponent("payload/original.zip").path))
        XCTAssertEqual(try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: root).conversations.count, 1)
    }
    func testSelectedDATStagesVerifiedBytesWithDecoderSuffixAndOriginalReceipt() throws {
        try withRoot { root, _ in
            let source = try XCTUnwrap(Bundle.module.url(forResource: "dat-assets", withExtension: "zip", subdirectory: "Fixtures")).resolvingSymlinksInPath()
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let files = try ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root)
            XCTAssertEqual(files.items.filter { $0.relativePath.hasSuffix(".dat") }.count, 4)
            let message = try XCTUnwrap(ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root).items.first)
            for (path, suffix) in [("assets/text.dat", "txt"), ("assets/image.dat", "png"), ("assets/document.dat", "pdf")] {
                let file = try XCTUnwrap(files.items.first { $0.relativePath == path })
                let candidate = try ArchiveRestoreService.manualAttachmentCandidate(review: review, jobsRoot: root, file: file, message: message)
                let staged = try ArchiveRestoreService.stageAttachment(candidate: candidate, review: review, jobsRoot: root)
                XCTAssertEqual(staged.pathExtension, suffix)
                XCTAssertEqual(candidate.source.relativePath, path)
                XCTAssertEqual(candidate.source.origin, .userReviewed)
                let bytes = try Data(contentsOf: staged)
                XCTAssertEqual(UInt64(bytes.count), file.bytes)
                XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), file.sha256)
                try FileManager.default.removeItem(at: staged)
            }
            let opaque = try XCTUnwrap(files.items.first { $0.relativePath == "assets/unknown.dat" })
            let candidate = try ArchiveRestoreService.manualAttachmentCandidate(review: review, jobsRoot: root, file: opaque, message: message)
            XCTAssertThrowsError(try ArchiveRestoreService.stageAttachment(candidate: candidate, review: review, jobsRoot: root))
            let job = root.appendingPathComponent(review.jobID.uuidString)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: job.appendingPathComponent("attachment-staging").path), [])
            XCTAssertTrue(FileManager.default.fileExists(atPath: job.appendingPathComponent("payload/original.zip").path))
            XCTAssertEqual(try ArchiveRestoreService.listReadyReviews(jobsRoot: root).map(\.jobID), [review.jobID])
        }
    }
    func testFormatReportUsesFullBoundInventoryInReadyAndCommittedStates() throws {
        try withRoot { root, source in
            let review = try ArchiveRestoreService.prepare(source: source, jobsRoot: root, expectedEpoch: UUID())
            let report = try ArchiveRestoreService.formatReport(review: review, jobsRoot: root)
            XCTAssertEqual(report.retainedFiles, 3)
            XCTAssertEqual(report.supportedExtensionFiles, 2)
            XCTAssertEqual(report.otherFiles, 1)
            XCTAssertEqual(report.conversationCount, 1)
            XCTAssertEqual(report.messageCount, 2)
            XCTAssertEqual(report.metadata, [.legacyConversations])
            try ArchiveRestoreService.markCommitted(review: review, jobsRoot: root)
            XCTAssertEqual(try ArchiveRestoreService.formatReport(review: review, jobsRoot: root), report)
            let inventory = root.appendingPathComponent(review.jobID.uuidString).appendingPathComponent("inventory.json")
            try Data("[]".utf8).write(to: inventory)
            XCTAssertThrowsError(try ArchiveRestoreService.formatReport(review: review, jobsRoot: root))
        }
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

extension ArchiveRestoreServiceTests {
    func withLegacyAsset(_ body: (URL, ArchiveRestoreService.Review) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = try XCTUnwrap(Bundle.module.url(forResource: "legacy-assets", withExtension: "zip", subdirectory: "Fixtures")).resolvingSymlinksInPath()
        try body(root, ArchiveRestoreService.prepare(source: zip, jobsRoot: root, expectedEpoch: UUID()))
    }
    func chosen(_ review: ArchiveRestoreService.Review, _ root: URL) throws -> ArchiveRestoreService.AttachmentCandidate {
        let file = try XCTUnwrap(ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root).items.first { $0.relativePath == "assets/note.txt" })
        let message = try XCTUnwrap(ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root).items.first)
        return try ArchiveRestoreService.manualAttachmentCandidate(review: review, jobsRoot: root, file: file, message: message)
    }
    func testManualListsAndSelectionDoNotRequireExportMap() throws {
        try withLegacyAsset { root, review in
            let page = try ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root)
            XCTAssertEqual(page.items.map(\.relativePath), ["assets/note.txt", "conversations.json"])
            XCTAssertEqual(page.unavailableCount, 1)
            let messages = try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root)
            XCTAssertEqual(messages.totalCount, 2)
            XCTAssertEqual(messages.items.first?.messageID.uuidString, "00000000-0000-0000-0000-000000000102")
            let candidate = try chosen(review, root)
            XCTAssertEqual(candidate.source.relativePath, "assets/note.txt")
            XCTAssertEqual(candidate.source.origin, .userReviewed)
            let inventoryBytes = try Data(contentsOf: root.appendingPathComponent(review.jobID.uuidString + "/inventory.json"))
            XCTAssertEqual(candidate.source.mapSHA256, SHA256.hash(data: inventoryBytes).map { String(format: "%02x", $0) }.joined())
            XCTAssertEqual(try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root).totalRecords, review.unresolvedCount)
            try ArchiveRestoreService.markCommitted(review: review, jobsRoot: root)
            XCTAssertEqual(try chosen(review, root), candidate)
        }
    }
    func testExactManualCandidateCopiesVerifiedBytesAndPreservesOriginal() throws {
        try withLegacyAsset { root, review in
            let candidate = try chosen(review, root)
            let url = try ArchiveRestoreService.stageAttachment(candidate: candidate, review: review, jobsRoot: root)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Synthetic attachment, not private data.\n")
            XCTAssertEqual(url.pathExtension, "txt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(review.jobID.uuidString + "/payload/original.zip").path))
            XCTAssertEqual(try chosen(review, root), candidate)
        }
    }
    func testChangedManualFileOrPlanFailClosed() throws {
        for changedPath in ["plan.json", "payload/extracted/assets/note.txt", "inventory.json"] {
            try withLegacyAsset { root, review in
                let candidate = try chosen(review, root)
                try Data("tampered".utf8).write(to: root.appendingPathComponent(review.jobID.uuidString + "/" + changedPath))
                XCTAssertThrowsError(try ArchiveRestoreService.stageAttachment(candidate: candidate, review: review, jobsRoot: root))
            }
        }
    }
    func testManualMessagesQueryAndSelectionMetadataAreBound() throws {
        try withLegacyAsset { root, review in
            let all = try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root)
            let answer = try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root, query: "ANSWER")
            XCTAssertEqual(answer.totalCount, 1); XCTAssertEqual(answer.items.first?.messageIndex, 2)
            XCTAssertEqual(try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root, query: ".*").totalCount, 0)
            XCTAssertThrowsError(try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root, query: String(repeating: "x", count: 201)))
            XCTAssertThrowsError(try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root, offset: -1))
            XCTAssertThrowsError(try ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root, offset: Int.max))
            let file = try XCTUnwrap(ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root).items.first)
            let msg = try XCTUnwrap(all.items.first)
            let altered = ArchiveRestoreService.AttachmentMessage(conversationID: msg.conversationID, messageID: msg.messageID, title: "tampered", messageIndex: msg.messageIndex, contentSnippet: msg.contentSnippet)
            XCTAssertThrowsError(try ArchiveRestoreService.manualAttachmentCandidate(review: review, jobsRoot: root, file: file, message: altered))
            let wrong = ArchiveRestoreService.AttachmentFile(relativePath: file.relativePath, bytes: file.bytes + 1, sha256: file.sha256)
            XCTAssertThrowsError(try ArchiveRestoreService.manualAttachmentCandidate(review: review, jobsRoot: root, file: wrong, message: msg))
        }
    }

}

extension ArchiveRestoreServiceTests {
    func testVerifiedAssetCopyRejectsAncestorSymlinkAndPreservesExistingDestination() throws {
        try withLegacyAsset { root, review in
            let candidate = try chosen(review, root)
            let extracted = root.appendingPathComponent(review.jobID.uuidString + "/payload/extracted")
            let output = root.appendingPathComponent("existing.txt")
            try Data("keep".utf8).write(to: output)
            XCTAssertThrowsError(try ArchiveVerifiedAssetCopy.copy(root: extracted, source: candidate.source, to: output))
            XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "keep")
            let assets = extracted.appendingPathComponent("assets")
            let moved = root.appendingPathComponent("moved-assets")
            try FileManager.default.moveItem(at: assets, to: moved)
            try FileManager.default.createSymbolicLink(at: assets, withDestinationURL: moved)
            let absent = root.appendingPathComponent("absent.txt")
            XCTAssertThrowsError(try ArchiveVerifiedAssetCopy.copy(root: extracted, source: candidate.source, to: absent))
            XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
        }
    }
    func testVerifiedAssetCopyRejectsChangedDigestAndRemovesOnlyOwnedPartial() throws {
        try withLegacyAsset { root, review in
            let candidate = try chosen(review, root)
            let extracted = root.appendingPathComponent(review.jobID.uuidString + "/payload/extracted")
            var wrong = candidate.source; wrong.sha256 = String(repeating: "0", count: 64)
            let output = root.appendingPathComponent("new.txt")
            XCTAssertThrowsError(try ArchiveVerifiedAssetCopy.copy(root: extracted, source: wrong, to: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent(wrong.relativePath).path))
        }
    }
}

extension ArchiveRestoreServiceTests {
    func testChangedCandidateMessageEpochOrSourceCannotBeStaged() throws {
        try withLegacyAsset { root, review in
            let candidate = try chosen(review, root)
            var alteredMessage = candidate.originalMessage; alteredMessage.content = "unreviewed replacement"
            var alteredSource = candidate.source; alteredSource.relativePath = "assets/other.txt"
            let changes: [ArchiveRestoreService.AttachmentCandidate] = [
                .init(source: candidate.source, expectedEpoch: UUID(), originalMessage: candidate.originalMessage, title: candidate.title, messageIndex: candidate.messageIndex),
                .init(source: candidate.source, expectedEpoch: candidate.expectedEpoch, originalMessage: alteredMessage, title: candidate.title, messageIndex: candidate.messageIndex),
                .init(source: alteredSource, expectedEpoch: candidate.expectedEpoch, originalMessage: candidate.originalMessage, title: candidate.title, messageIndex: candidate.messageIndex)
            ]
            for changed in changes {
                XCTAssertThrowsError(try ArchiveRestoreService.stageAttachment(candidate: changed, review: review, jobsRoot: root))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(review.jobID.uuidString + "/attachment-staging").path))
        }
    }
}

extension ArchiveRestoreServiceTests {
    func bindSyntheticPlan(_ plan: ArchiveRestoreService.Plan, review: inout ArchiveRestoreService.Review, root: URL) throws {
        let job = root.appendingPathComponent(review.jobID.uuidString)
        let bytes = try JSONEncoder().encode(plan)
        review.conversationCount = plan.conversations.count
        review.messageCount = plan.conversations.reduce(0) { $0 + $1.messages.count }
        review.unresolvedCount = plan.unresolved.count
        var state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: job.appendingPathComponent("state.json"))) as? [String: Any])
        state["review"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(review))
        state["planSHA256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try bytes.write(to: job.appendingPathComponent("plan.json"))
        try JSONSerialization.data(withJSONObject: state).write(to: job.appendingPathComponent("state.json"))
    }
    func testManualContextRejectsDuplicateMessagesConversationsAndOrphans() throws {
        for mode in 0..<3 {
            try withLegacyAsset { root, originalReview in
                var review = originalReview
                var plan = try JSONDecoder().decode(ArchiveRestoreService.Plan.self, from: Data(contentsOf: root.appendingPathComponent(review.jobID.uuidString + "/plan.json")))
                if mode == 0 { plan.conversations[0].messages.append(plan.conversations[0].messages[0]) }
                if mode == 1 { plan.conversations.append(plan.conversations[0]) }
                if mode == 2 { plan.unresolved.append(.init(messageID: UUID(), source: "contentPart", originalJSON: Data("{}".utf8))) }
                try bindSyntheticPlan(plan, review: &review, root: root)
                XCTAssertThrowsError(try ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root))
                XCTAssertThrowsError(try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root))
            }
        }
    }
    func testManualMessagesPageFiftyBoundLabelsAndPreservePlan() throws {
        try withLegacyAsset { root, originalReview in
            var review = originalReview
            let url = root.appendingPathComponent(review.jobID.uuidString + "/plan.json")
            var plan = try JSONDecoder().decode(ArchiveRestoreService.Plan.self, from: Data(contentsOf: url))
            plan.conversations[0].title = "Synthetic\n" + String(repeating: "t", count: 300)
            plan.conversations[0].messages = (0..<103).map { index in ChatMessage(role: .user, content: "Row \(index)\n" + String(repeating: "x", count: 300)) }
            try bindSyntheticPlan(plan, review: &review, root: root)
            let before = try Data(contentsOf: url)
            let first = try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root)
            XCTAssertEqual(first.totalCount, 103); XCTAssertEqual(first.items.count, 50); XCTAssertEqual(first.nextOffset, 50)
            XCTAssertEqual(first.items.first?.title.unicodeScalars.count, 200)
            XCTAssertEqual(first.items.first?.contentSnippet.unicodeScalars.count, 200)
            XCTAssertFalse(first.items[0].contentSnippet.contains("\n"))
            let last = try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root, offset: 100)
            XCTAssertEqual(last.items.count, 3); XCTAssertNil(last.nextOffset); XCTAssertEqual(last.items[0].messageIndex, 101)
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }
    func testManualContextRejectsDuplicateInventoryPathsAndAlteredReview() throws {
        try withLegacyAsset { root, review in
            var altered = review; altered.messageCount += 1
            XCTAssertThrowsError(try ArchiveRestoreService.attachmentFiles(review: altered, jobsRoot: root))
            let job = root.appendingPathComponent(review.jobID.uuidString)
            let inventoryURL = job.appendingPathComponent("inventory.json")
            var files = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: inventoryURL)) as? [[String: Any]])
            files[1] = files[0]
            let bytes = try JSONSerialization.data(withJSONObject: files)
            var state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: job.appendingPathComponent("state.json"))) as? [String: Any])
            state["inventorySHA256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            try bytes.write(to: inventoryURL)
            try JSONSerialization.data(withJSONObject: state).write(to: job.appendingPathComponent("state.json"))
            XCTAssertThrowsError(try ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root))
        }
    }
}
