import XCTest
@testable import JarvisEVO

final class PluginExecutionTests: XCTestCase {
    private let connection = UUID()
    private let revision = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReviewCopiesExactArgumentsAndCanBeConsumedOnlyOnce() throws {
        var gate = PluginReviewGate()
        let arguments = MCPJSONValue.object(["text": .string("Only this explicit text")])
        let review = try gate.prepare(connectionID: connection, catalogRevision: revision,
            toolName: "workspace.read", arguments: arguments, now: now)
        let consumed = try gate.consume(id: review.id, connectionID: connection, catalogRevision: revision, now: now)
        XCTAssertEqual(consumed.arguments, arguments)
        XCTAssertEqual(consumed.toolName, "workspace.read")
        XCTAssertEqual(consumed.connectionID, connection)
        XCTAssertThrowsError(try gate.consume(id: review.id, connectionID: connection, catalogRevision: revision, now: now))
    }

    func testChangingConnectionOrCatalogCannotReuseApproval() throws {
        for changeConnection in [true, false] {
            var gate = PluginReviewGate()
            let review = try gate.prepare(connectionID: connection, catalogRevision: revision,
                toolName: "tool", arguments: .object([:]), now: now)
            XCTAssertThrowsError(try gate.consume(id: review.id,
                connectionID: changeConnection ? UUID() : connection,
                catalogRevision: changeConnection ? revision : UUID(), now: now))
        }
    }

    func testNewReviewInvalidatesOldEvenWhenArgumentsAreLaterRestored() throws {
        var gate = PluginReviewGate()
        let first = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        _ = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "b", arguments: .object([:]), now: now)
        let third = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertNotEqual(first.id, third.id)
        XCTAssertThrowsError(try gate.consume(id: first.id, connectionID: connection, catalogRevision: revision, now: now))
    }

    func testExplicitInvalidationAndExpiryNeverReturnApproval() throws {
        var gate = PluginReviewGate()
        let first = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        gate.invalidate()
        XCTAssertThrowsError(try gate.consume(id: first.id, connectionID: connection, catalogRevision: revision, now: now))
        let expired = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertThrowsError(try gate.consume(id: expired.id, connectionID: connection, catalogRevision: revision, now: now.addingTimeInterval(301)))
    }

    func testExactFiveMinuteBoundaryIsAcceptedButClockReversalIsNot() throws {
        var gate = PluginReviewGate()
        let edge = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertNoThrow(try gate.consume(id: edge.id, connectionID: connection, catalogRevision: revision, now: now.addingTimeInterval(300)))
        let reversed = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertThrowsError(try gate.consume(id: reversed.id, connectionID: connection, catalogRevision: revision, now: now.addingTimeInterval(-1)))
    }

    func testOversizedArgumentsAndUnsafeNamesAreRejectedWithoutReview() {
        var gate = PluginReviewGate()
        XCTAssertThrowsError(try gate.prepare(connectionID: connection, catalogRevision: revision,
            toolName: "tool", arguments: .object(["value": .string(String(repeating: "x", count: 16_384))]), now: now))
        for name in ["", "tool\nname", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try gate.prepare(connectionID: connection, catalogRevision: revision,
                toolName: name, arguments: .object([:]), now: now))
        }
    }
}

@MainActor
final class PluginJournalTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testDispatchRecordExistsBeforeReturningAndRelaunchMarksItUnknown() throws {
        let journal = try PluginJournal(directory: directory)
        let id = try journal.begin(connectionID: UUID(), toolName: "workspace.write")
        XCTAssertEqual(journal.records.first?.id, id)
        XCTAssertEqual(journal.records.first?.state, .running)
        let reopened = try PluginJournal(directory: directory)
        XCTAssertEqual(reopened.records.first?.id, id)
        XCTAssertEqual(reopened.records.first?.state, .unknown)
        XCTAssertFalse(reopened.records.contains { $0.state == .running })
    }

    func testConfirmedResultAndToolErrorRemainDistinctAcrossRelaunch() throws {
        let journal = try PluginJournal(directory: directory)
        let success = try journal.begin(connectionID: UUID(), toolName: "read")
        try journal.finish(id: success, state: .serverReportedSuccess)
        let failure = try journal.begin(connectionID: UUID(), toolName: "write")
        try journal.finish(id: failure, state: .serverReportedError)
        let reopened = try PluginJournal(directory: directory)
        XCTAssertEqual(reopened.records.first { $0.id == success }?.state, .serverReportedSuccess)
        XCTAssertEqual(reopened.records.first { $0.id == failure }?.state, .serverReportedError)
    }

    func testUnknownOutcomeIsNotRewrittenAsCanceledOrAutomaticallyReplayed() throws {
        let journal = try PluginJournal(directory: directory)
        let id = try journal.begin(connectionID: UUID(), toolName: "write")
        try journal.finish(id: id, state: .unknown)
        let reopened = try PluginJournal(directory: directory)
        XCTAssertEqual(reopened.records.first?.state, .unknown)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertThrowsError(try reopened.finish(id: id, state: .serverReportedSuccess), "A new run cannot invent a late confirmation for an already unknown operation.")
    }

    func testJournalWriteFailurePreventsCreatingAnExecutionRecord() throws {
        let journal = try PluginJournal(directory: directory)
        try FileManager.default.removeItem(at: directory)
        try Data("Not a directory".utf8).write(to: directory)
        XCTAssertThrowsError(try journal.begin(connectionID: UUID(), toolName: "write"))
        XCTAssertTrue(journal.records.isEmpty)
    }

    func testCorruptJournalIsPreservedRatherThanSilentlyReset() throws {
        let file = directory.appendingPathComponent("plugin-executions.json")
        let original = Data("{ broken journal".utf8); try original.write(to: file)
        XCTAssertThrowsError(try PluginJournal(directory: directory))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testBoundedJournalRetainsOnlyOneHundredCompletedRecords() throws {
        let journal = try PluginJournal(directory: directory)
        for _ in 0..<105 {
            let id = try journal.begin(connectionID: UUID(), toolName: "read")
            try journal.finish(id: id, state: .serverReportedSuccess)
        }
        XCTAssertEqual(journal.records.count, 100)
        XCTAssertEqual(try PluginJournal(directory: directory).records.count, 100)
    }
}
