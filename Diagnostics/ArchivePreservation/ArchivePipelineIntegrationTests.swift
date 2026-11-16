import XCTest
import ArchiveExtraction
@testable import Preservation

/// Synthetic component integration, not app/Files/provider/database verification.
final class ArchivePipelineIntegrationTests: XCTestCase {
    private func withFixture(_ name: String, body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "zip", subdirectory: "Fixtures"))
        let source = root.appendingPathComponent("source.zip")
        try FileManager.default.copyItem(at: fixture, to: source)
        try body(source, root.appendingPathComponent("staging"))
    }
    func testPreserveRevalidateExtractRetainsOriginalAndExactBytes() throws {
        try withFixture("valid") { source, staging in
            let original = try Data(contentsOf: source)
            let manifest = try ArchivePreservation.preserve(source: source, staging: staging)
            XCTAssertEqual(try ArchivePreservation.revalidate(staging: staging, expected: manifest), manifest)
            let destination = staging.appendingPathComponent("extracted")
            let entries = try ZIPExtractor.extract(source: staging.appendingPathComponent("original.zip"), destination: destination)
            XCTAssertEqual(entries.map(\.path), ["conversation.txt", "assets/repeated.bin", "conversations.json"])
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("conversation.txt")), Data("Synthetic conversation, not private history.\n".utf8))
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("assets/repeated.bin")), Data(repeating: 97, count: 300_000))
            let conversations = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("conversations.json"))) as? [[String: Any]])
            XCTAssertEqual(conversations.count, 1)
            XCTAssertEqual(conversations.first?["title"] as? String, "Synthetic import")
            XCTAssertEqual((conversations.first?["mapping"] as? [String: Any])?.count, 2)
            XCTAssertEqual(conversations.first?["current_node"] as? String, "reply")
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("original.zip")), original)
            XCTAssertEqual(try ArchivePreservation.revalidate(staging: staging, expected: manifest), manifest)
        }
    }
    func testModifiedPreservedArchiveCannotPassPreExtractionGate() throws {
        try withFixture("valid") { source, staging in
            let original = try Data(contentsOf: source)
            let manifest = try ArchivePreservation.preserve(source: source, staging: staging)
            let archive = staging.appendingPathComponent("original.zip")
            var corrupt = try Data(contentsOf: archive); corrupt[corrupt.count / 2] ^= 1
            try corrupt.write(to: archive)
            XCTAssertThrowsError(try ArchivePreservation.revalidate(staging: staging, expected: manifest))
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("extracted").path))
        }
    }
    func testCRCFailureRetainsBothSourceAndPreservedOriginal() throws {
        try withFixture("crc-failure") { source, staging in
            let original = try Data(contentsOf: source)
            let manifest = try ArchivePreservation.preserve(source: source, staging: staging)
            XCTAssertEqual(try ArchivePreservation.revalidate(staging: staging, expected: manifest), manifest)
            XCTAssertThrowsError(try ZIPExtractor.extract(source: staging.appendingPathComponent("original.zip"), destination: staging.appendingPathComponent("extracted"))) { error in
                guard case ZIPExtractor.Failure.invalidArchive = error else { return XCTFail("Expected CRC rejection, got \(error)") }
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("extracted/conversation.txt").path))
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("original.zip")), original)
            XCTAssertEqual(try ArchivePreservation.revalidate(staging: staging, expected: manifest), manifest)
        }
    }

    func testPreservedZIPStreamsIntoRealConversationModelsWithoutMutatingOriginal() throws {
        try withFixture("valid") { source, staging in
            let original = try Data(contentsOf: source)
            let manifest = try ArchivePreservation.preserve(source: source, staging: staging)
            _ = try ArchivePreservation.revalidate(staging: staging, expected: manifest)
            let extracted = staging.appendingPathComponent("extracted")
            _ = try ZIPExtractor.extract(source: staging.appendingPathComponent("original.zip"), destination: extracted)
            let handle = try FileHandle(forReadingFrom: extracted.appendingPathComponent("conversations.json"))
            defer { try? handle.close() }
            var prepared: [ChatGPTConversationRestore.Result] = []
            let report = try ChatGPTRecordStream.read(handle) {
                prepared.append(try ChatGPTConversationRestore.convert($0, identities: [:]))
            }
            XCTAssertEqual(report.records, 1)
            let conversation = try XCTUnwrap(prepared.first?.conversation)
            XCTAssertEqual(conversation.title, "Synthetic import")
            XCTAssertEqual(conversation.messages.map(\.content), ["Synthetic saved question", "Synthetic saved answer"])
            XCTAssertEqual(conversation.messages.map(\.role), [.user, .assistant])
            XCTAssertEqual(conversation.messages.map(\.state), [.complete, .complete])
            XCTAssertEqual(prepared.first?.omittedMessages, 0)
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(try ArchivePreservation.revalidate(staging: staging, expected: manifest), manifest)
            // No database/UI is exercised and no activation is claimed by this proof.
        }
    }
}
