import XCTest
@testable import JarvisEVO

@MainActor
final class PluginJournalTests: XCTestCase {
    private var directory: URL!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    func testDispatchRecordExistsBeforeReturningAndRelaunchMarksItUnknown() async throws {
        let journal = try PluginJournal(directory: directory)
        let id = try journal.begin(connectionID: UUID(), toolName: "workspace.write")
        XCTAssertEqual(journal.records.first?.id, id)
        XCTAssertEqual(journal.records.first?.state, .running)
        let reopened = try PluginJournal(directory: directory)
        XCTAssertEqual(reopened.records.first?.id, id)
        XCTAssertEqual(reopened.records.first?.state, .unknown)
        XCTAssertFalse(reopened.records.contains { $0.state == .running })
    }

    func testConfirmedResultAndToolErrorRemainDistinctAcrossRelaunch() async throws {
        let journal = try PluginJournal(directory: directory)
        let success = try journal.begin(connectionID: UUID(), toolName: "read")
        try journal.finish(id: success, state: .serverReportedSuccess)
        let failure = try journal.begin(connectionID: UUID(), toolName: "write")
        try journal.finish(id: failure, state: .serverReportedError)
        let reopened = try PluginJournal(directory: directory)
        XCTAssertEqual(reopened.records.first { $0.id == success }?.state, .serverReportedSuccess)
        XCTAssertEqual(reopened.records.first { $0.id == failure }?.state, .serverReportedError)
    }

    func testUnknownOutcomeIsNotRewrittenAsCanceledOrAutomaticallyReplayed() async throws {
        let journal = try PluginJournal(directory: directory)
        let id = try journal.begin(connectionID: UUID(), toolName: "write")
        try journal.finish(id: id, state: .unknown)
        let reopened = try PluginJournal(directory: directory)
        XCTAssertEqual(reopened.records.first?.state, .unknown)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertThrowsError(try reopened.finish(id: id, state: .serverReportedSuccess), "A new run cannot invent a late confirmation for an already unknown operation.")
    }

    func testJournalWriteFailurePreventsCreatingAnExecutionRecord() async throws {
        let journal = try PluginJournal(directory: directory)
        try FileManager.default.removeItem(at: directory)
        try Data("Not a directory".utf8).write(to: directory)
        XCTAssertThrowsError(try journal.begin(connectionID: UUID(), toolName: "write"))
        XCTAssertTrue(journal.records.isEmpty)
    }

    func testCorruptJournalIsPreservedRatherThanSilentlyReset() async throws {
        let file = directory.appendingPathComponent("plugin-executions.json")
        let original = Data("{ broken journal".utf8); try original.write(to: file)
        XCTAssertThrowsError(try PluginJournal(directory: directory))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testBoundedJournalRetainsOnlyOneHundredCompletedRecords() async throws {
        let journal = try PluginJournal(directory: directory)
        for _ in 0..<105 {
            let id = try journal.begin(connectionID: UUID(), toolName: "read")
            try journal.finish(id: id, state: .serverReportedSuccess)
        }
        XCTAssertEqual(journal.records.count, 100)
        XCTAssertEqual(try PluginJournal(directory: directory).records.count, 100)
    }
}
