import XCTest
import CryptoKit
@testable import OrivynVMProof

@MainActor
final class VMCheckpointStoreTests: XCTestCase {
    private let identity = VMCheckpointIdentity(engineSHA256: String(repeating: "a", count: 64), guestSHA256: String(repeating: "b", count: 64), configurationSHA256: String(repeating: "c", count: 64))
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func rejects(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected rejection", file: file, line: line) } catch { }
    }
    func testRoundTripChunkedStateSurvivesStoreRecreation() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        let data = Data(repeating: 42, count: VMCheckpointStore.chunkBytes + 7)
        let id = try await store.begin(identity: identity, expectedBytes: data.count)
        let firstOffset = try await store.append(transaction: id, offset: 0, data: Data(data.prefix(VMCheckpointStore.chunkBytes)))
        XCTAssertEqual(firstOffset, VMCheckpointStore.chunkBytes)
        _ = try await store.append(transaction: id, offset: firstOffset, data: Data(data.suffix(7)))
        let saved = try await store.commit(transaction: id)
        XCTAssertEqual(saved.sha256, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        let reopened = try VMCheckpointStore(root: root)
        let latest = try await reopened.latest(identity: identity)
        XCTAssertEqual(latest, saved)
        let chunk = try await reopened.read(identity: identity, generation: saved.generation, offset: firstOffset, length: 7)
        XCTAssertEqual(chunk, Data(repeating: 42, count: 7))
    }
    func testBadChunkAndStaleTransactionAreRejected() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        let id = try await store.begin(identity: identity, expectedBytes: 4)
        await rejects { _ = try await store.append(transaction: id, offset: 1, data: Data([1])) }
        await rejects { _ = try await store.append(transaction: id, offset: 0, data: Data(repeating: 1, count: VMCheckpointStore.chunkBytes + 1)) }
        await rejects { _ = try await store.commit(transaction: id) }
        try await store.abort(transaction: id)
        await rejects { _ = try await store.append(transaction: id, offset: 0, data: Data([1])) }
        await rejects { _ = try await store.begin(identity: self.identity, expectedBytes: VMCheckpointStore.maximumBytes + 1) }
    }
    func testFailedReplacementPreservesPublishedGeneration() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        let first = try await store.begin(identity: identity, expectedBytes: 1)
        _ = try await store.append(transaction: first, offset: 0, data: Data([7]))
        let saved = try await store.commit(transaction: first)
        let second = try await store.begin(identity: identity, expectedBytes: 1, expectedSHA256: String(repeating: "0", count: 64))
        _ = try await store.append(transaction: second, offset: 0, data: Data([8]))
        await rejects { _ = try await store.commit(transaction: second) }
        let latest = try await store.latest(identity: identity)
        XCTAssertEqual(latest, saved)
        try await store.abort(transaction: second)
    }
    func testCorruptionAndIdentityMismatchCannotRestore() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        let id = try await store.begin(identity: identity, expectedBytes: 2)
        _ = try await store.append(transaction: id, offset: 0, data: Data([1, 2]))
        let saved = try await store.commit(transaction: id)
        let wrong = VMCheckpointIdentity(engineSHA256: String(repeating: "f", count: 64), guestSHA256: identity.guestSHA256, configurationSHA256: identity.configurationSHA256)
        await rejects { _ = try await store.latest(identity: wrong) }
        try Data([8, 9]).write(to: root.appendingPathComponent("g-" + saved.generation.uuidString).appendingPathComponent("state.bin"))
        await rejects { _ = try await store.latest(identity: self.identity) }
    }
    func testSymlinkRootAndStateRefused() async throws {
        let parent = try directory(); defer { try? FileManager.default.removeItem(at: parent) }
        let target = parent.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try VMCheckpointStore(root: link))
        let store = try VMCheckpointStore(root: target)
        let id = try await store.begin(identity: identity, expectedBytes: 1)
        _ = try await store.append(transaction: id, offset: 0, data: Data([7]))
        let saved = try await store.commit(transaction: id)
        let state = target.appendingPathComponent("g-" + saved.generation.uuidString).appendingPathComponent("state.bin")
        let external = parent.appendingPathComponent("external"); try Data([7]).write(to: external)
        try FileManager.default.removeItem(at: state)
        try FileManager.default.createSymbolicLink(at: state, withDestinationURL: external)
        await rejects { _ = try await store.latest(identity: self.identity) }
    }
    func testGenerationPinAndMutationDuringRestore() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        let empty = try await store.latest(identity: identity); XCTAssertNil(empty)
        let first = try await store.begin(identity: identity, expectedBytes: 1)
        _ = try await store.append(transaction: first, offset: 0, data: Data([1]))
        let old = try await store.commit(transaction: first)
        let second = try await store.begin(identity: identity, expectedBytes: 1)
        _ = try await store.append(transaction: second, offset: 0, data: Data([2]))
        _ = try await store.commit(transaction: second)
        let oldData = try await store.read(identity: identity, generation: old.generation, offset: 0, length: 1)
        XCTAssertEqual(oldData, Data([1]))
        try Data([3]).write(to: root.appendingPathComponent("g-" + old.generation.uuidString).appendingPathComponent("state.bin"))
        await rejects { _ = try await store.read(identity: self.identity, generation: old.generation, offset: 0, length: 1) }
        await rejects { _ = try await store.read(identity: self.identity, generation: old.generation, offset: -1, length: 1) }
    }
    func testMalformedPointerAndInvalidIdentityRejected() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        let wrong = VMCheckpointIdentity(engineSHA256: "../../outside", guestSHA256: identity.guestSHA256, configurationSHA256: identity.configurationSHA256)
        await rejects { _ = try await store.begin(identity: wrong, expectedBytes: 1) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("current.json"))
        await rejects { _ = try await store.latest(identity: self.identity) }
        try Data(repeating: 0, count: 4097).write(to: root.appendingPathComponent("current.json"))
        await rejects { _ = try await store.latest(identity: self.identity) }
    }

    func testExplicitPruneKeepsCurrentPreviousAndActiveRestore() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        var generations: [VMCheckpointMetadata] = []
        for byte in [UInt8(1), 2, 3] {
            let id = try await store.begin(identity: identity, expectedBytes: 1)
            _ = try await store.append(transaction: id, offset: 0, data: Data([byte]))
            generations.append(try await store.commit(transaction: id))
        }
        _ = try await store.read(identity: identity, generation: generations[0].generation, offset: 0, length: 1)
        let retained = try await store.prune(); XCTAssertEqual(retained, 0)
        _ = try await store.latest(identity: identity) // Ends the old read lease.
        let removed = try await store.prune(); XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("g-" + generations[0].generation.uuidString).path))
        for item in generations.suffix(2) { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("g-" + item.generation.uuidString).path)) }
        let active = try await store.begin(identity: identity, expectedBytes: 2)
        _ = try await store.append(transaction: active, offset: 0, data: Data([9]))
        try await store.abort(transaction: active)
        let latest = try await store.latest(identity: identity); XCTAssertEqual(latest, generations[2])
    }

}
