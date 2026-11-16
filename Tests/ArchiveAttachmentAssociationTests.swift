import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(Association)
@testable import Association
#else
@testable import JarvisEVO
#endif

final class ArchiveAttachmentAssociationTests: XCTestCase {
    let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    let assetID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("abc".utf8).write(to: root.appendingPathComponent("assets/a.bin"))
        try body(root)
    }
    func reference(_ sourceID: String, message: UUID = UUID()) throws -> ArchiveAttachmentAssociation.Reference {
        .init(messageID: message, source: "contentPart", originalJSON: try JSONSerialization.data(withJSONObject: ["asset_pointer": sourceID]))
    }
    func testExactMappingProducesOwnedCopyPlanNotGuessedAppAttachment() throws {
        try fixture { root in
            let file = try ArchiveAttachmentAssociation.verify(root: root, relativePath: "assets/a.bin", bytes: 3, sha256: digest)
            let ref = try reference("sediment://synthetic")
            let plan = try ArchiveAttachmentAssociation.plan(root: root, references: [ref], mappings: [.init(sourceID: "sediment://synthetic", relativePath: "assets/a.bin")], files: [file], identities: ["sediment://synthetic": assetID])
            XCTAssertEqual(plan.copies.count, 1)
            XCTAssertEqual(plan.copies.first?.destinationName, assetID.uuidString + ".archive-asset")
            XCTAssertEqual(plan.associations.first?.messageID, ref.messageID)
            XCTAssertEqual(plan.references.first?.originalJSON, ref.originalJSON)
            XCTAssertTrue(plan.unresolved.isEmpty)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/a.bin")), Data("abc".utf8))
        }
    }
    func testRejectsBadHashSizeAndUnsafeOrLinkedPaths() throws {
        try fixture { root in
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("assets"))
            for (path, size, sha) in [("assets/a.bin", UInt64(4), digest), ("assets/a.bin", 3, String(repeating: "0", count: 64)), ("../a.bin", 3, digest), ("/assets/a.bin", 3, digest), ("linked/a.bin", 3, digest)] {
                XCTAssertThrowsError(try ArchiveAttachmentAssociation.verify(root: root, relativePath: path, bytes: size, sha256: sha))
            }
        }
    }
    func testAmbiguousMissingAndUnsupportedReferencesAreRetainedUnresolved() throws {
        try fixture { root in
            let file = try ArchiveAttachmentAssociation.verify(root: root, relativePath: "assets/a.bin", bytes: 3, sha256: digest)
            let refs = [try reference("duplicate"), try reference("missing"), ArchiveAttachmentAssociation.Reference(messageID: UUID(), source: "unknown", originalJSON: Data("{}".utf8))]
            let plan = try ArchiveAttachmentAssociation.plan(root: root, references: refs, mappings: [.init(sourceID: "duplicate", relativePath: "assets/a.bin"), .init(sourceID: "duplicate", relativePath: "assets/a.bin")], files: [file], identities: ["duplicate": assetID])
            XCTAssertTrue(plan.copies.isEmpty); XCTAssertTrue(plan.associations.isEmpty)
            XCTAssertEqual(plan.unresolved.count, 3)
            XCTAssertEqual(plan.references.map(\.originalJSON), refs.map(\.originalJSON))
        }
    }

    func testRepeatedReferencesShareOneOwnedCopyAndMetadataIDIsExact() throws {
        try fixture { root in
            let file = try ArchiveAttachmentAssociation.verify(root: root, relativePath: "assets/a.bin", bytes: 3, sha256: digest)
            let first = try reference("exact")
            let second = ArchiveAttachmentAssociation.Reference(messageID: UUID(), source: "attachmentMetadata", originalJSON: Data(#"{"id":"exact"}"#.utf8))
            let plan = try ArchiveAttachmentAssociation.plan(root: root, references: [first, second], mappings: [.init(sourceID: "exact", relativePath: "assets/a.bin")], files: [file], identities: ["exact": assetID])
            XCTAssertEqual(plan.copies.count, 1); XCTAssertEqual(plan.associations.count, 2)
            XCTAssertEqual(plan.associations.map(\.assetID), [assetID, assetID])
            XCTAssertEqual(plan.associations.map(\.referenceIndex), [0, 1])
        }
    }
    func testEvidenceFromAnotherExtractionRootCannotBeReused() throws {
        try fixture { root in try fixture { other in
            let file = try ArchiveAttachmentAssociation.verify(root: other, relativePath: "assets/a.bin", bytes: 3, sha256: digest)
            let plan = try ArchiveAttachmentAssociation.plan(root: root, references: [try reference("exact")], mappings: [.init(sourceID: "exact", relativePath: "assets/a.bin")], files: [file], identities: ["exact": assetID])
            XCTAssertTrue(plan.copies.isEmpty); XCTAssertEqual(plan.unresolved.count, 1)
        } }
    }
    func testMissingAndDuplicateDurableIdentitiesNeverInventUUIDs() throws {
        try fixture { root in
            let file = try ArchiveAttachmentAssociation.verify(root: root, relativePath: "assets/a.bin", bytes: 3, sha256: digest)
            for identities in [[:], ["exact": assetID, "another": assetID]] {
                let plan = try ArchiveAttachmentAssociation.plan(root: root, references: [try reference("exact")], mappings: [.init(sourceID: "exact", relativePath: "assets/a.bin")], files: [file], identities: identities)
                XCTAssertTrue(plan.copies.isEmpty); XCTAssertEqual(plan.unresolved.count, 1)
            }
        }
    }
    func testFIFOAndDirectoryInputsRejectedWithoutWaitingForWriter() throws {
        try fixture { root in
            XCTAssertEqual(mkfifo(root.appendingPathComponent("fifo").path, 0o600), 0)
            for path in ["fifo", "assets"] {
                XCTAssertThrowsError(try ArchiveAttachmentAssociation.verify(root: root, relativePath: path, bytes: 0, sha256: digest))
            }
        }
    }
    func testDuplicateFileEvidenceAndMalformedJSONStayUnresolved() throws {
        try fixture { root in
            let file = try ArchiveAttachmentAssociation.verify(root: root, relativePath: "assets/a.bin", bytes: 3, sha256: digest)
            let invalid = ArchiveAttachmentAssociation.Reference(messageID: UUID(), source: "contentPart", originalJSON: Data("not JSON".utf8))
            let plan = try ArchiveAttachmentAssociation.plan(root: root, references: [try reference("exact"), invalid], mappings: [.init(sourceID: "exact", relativePath: "assets/a.bin")], files: [file, file], identities: ["exact": assetID])
            XCTAssertTrue(plan.copies.isEmpty); XCTAssertEqual(plan.unresolved.count, 2)
            XCTAssertEqual(plan.references.last?.originalJSON, invalid.originalJSON)
        }
    }
    func testOversizedMetadataAndFileEvidenceRejected() throws {
        try fixture { root in
            let huge = ArchiveAttachmentAssociation.Reference(messageID: UUID(), source: "contentPart", originalJSON: Data(repeating: 32, count: 1_000_001))
            XCTAssertThrowsError(try ArchiveAttachmentAssociation.plan(root: root, references: [huge], mappings: [], files: [], identities: [:]))
            XCTAssertThrowsError(try ArchiveAttachmentAssociation.verify(root: root, relativePath: "assets/a.bin", bytes: 536_870_913, sha256: digest))
        }
    }
    func testCancelledPreparationDoesNotReturnEvidence() async throws {
        let expected = digest
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ArchiveAttachmentAssociation.verify(root: URL(fileURLWithPath: "/tmp"), relativePath: "unused", bytes: 0, sha256: expected)
        }
        do { _ = try await task.value; XCTFail("Cancelled verification returned evidence") }
        catch is CancellationError { }
    }

    func testOversizedMappingAndIdentityKeysAreBounded() throws {
        try fixture { root in
            let long = String(repeating: "x", count: 4097)
            XCTAssertThrowsError(try ArchiveAttachmentAssociation.plan(root: root, references: [], mappings: [.init(sourceID: long, relativePath: "assets/a.bin")], files: [], identities: [:]))
            XCTAssertThrowsError(try ArchiveAttachmentAssociation.plan(root: root, references: [], mappings: [], files: [], identities: [long: assetID]))
        }
    }
}
