import XCTest
@testable import JarvisEVO

final class PluginConnectionRemovalTests: XCTestCase {
    private enum Failure: Error, Equatable { case read, delete, metadata, restore }
    func testSuccessDeletesBeforeSavingMetadata() throws {
        var events: [String] = []; var credential: String? = "private fixture"
        try PluginConnectionRemoval.perform(readCredential: { events.append("read"); return credential }, writeCredential: { credential = $0; events.append($0 == nil ? "delete" : "restore") }, saveMetadata: { events.append("metadata") })
        XCTAssertNil(credential); XCTAssertEqual(events, ["read", "delete", "metadata"])
    }
    func testMetadataFailureRestoresPriorTokenAndRethrowsOriginalError() {
        var credential: String? = "private fixture"; var writes = 0
        XCTAssertThrowsError(try PluginConnectionRemoval.perform(readCredential: { credential }, writeCredential: { credential = $0; writes += 1 }, saveMetadata: { throw Failure.metadata })) {
            XCTAssertEqual($0 as? Failure, .metadata)
        }
        XCTAssertEqual(credential, "private fixture"); XCTAssertEqual(writes, 2)
    }
    func testMetadataFailureRestoresAbsentCredentialWithoutInventingOne() {
        var writes: [String?] = []
        XCTAssertThrowsError(try PluginConnectionRemoval.perform(readCredential: { nil }, writeCredential: { writes.append($0) }, saveMetadata: { throw Failure.metadata })) { XCTAssertEqual($0 as? Failure, .metadata) }
        XCTAssertEqual(writes.count, 2); XCTAssertTrue(writes.allSatisfy { $0 == nil })
    }
    func testReadFailureDoesNotDeleteOrSaveMetadata() {
        var changed = false
        XCTAssertThrowsError(try PluginConnectionRemoval.perform(readCredential: { throw Failure.read }, writeCredential: { _ in changed = true }, saveMetadata: { changed = true })) { XCTAssertEqual($0 as? Failure, .read) }
        XCTAssertFalse(changed)
    }
    func testDeleteFailureDoesNotSaveMetadata() {
        var saved = false
        XCTAssertThrowsError(try PluginConnectionRemoval.perform(readCredential: { "fixture" }, writeCredential: { _ in throw Failure.delete }, saveMetadata: { saved = true })) { XCTAssertEqual($0 as? Failure, .delete) }
        XCTAssertFalse(saved)
    }
    func testRollbackFailureRequiresRecoveryWithoutLeakingUnderlyingError() {
        var writes = 0
        XCTAssertThrowsError(try PluginConnectionRemoval.perform(readCredential: { "secret fixture" }, writeCredential: { _ in writes += 1; if writes == 2 { throw NSError(domain: "secret fixture", code: 1) } }, saveMetadata: { throw Failure.metadata })) {
            XCTAssertEqual($0 as? PluginConnectionRemovalError, .recoveryRequired)
            XCTAssertFalse($0.localizedDescription.contains("secret fixture"))
            XCTAssertTrue($0.localizedDescription.contains("credential"))
        }
        XCTAssertEqual(writes, 2)
    }
}
