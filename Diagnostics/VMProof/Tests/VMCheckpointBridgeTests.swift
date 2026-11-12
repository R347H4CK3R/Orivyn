import XCTest
import WebKit
@testable import OrivynVMProof

@MainActor
final class VMCheckpointBridgeTests: XCTestCase {
    private let identity = VMCheckpointIdentity(engineSHA256: String(repeating: "a", count: 64), guestSHA256: String(repeating: "b", count: 64), configurationSHA256: String(repeating: "c", count: 64))
    private var identityBody: [String: Any] { ["engineSHA256": identity.engineSHA256, "guestSHA256": identity.guestSHA256, "configurationSHA256": identity.configurationSHA256] }
    func testParserRejectsWrongOwnerExtraKeysBooleanNumbersAndWrongIdentity() throws {
        let owner = UUID()
        var value: [String: Any] = ["owner":owner.uuidString,"action":"begin","identity":identityBody,"expectedBytes":4]
        XCTAssertNoThrow(try VMCheckpointRequest.parse(value, owner: owner, identity: identity))
        value["path"] = "/tmp/private"; XCTAssertThrowsError(try VMCheckpointRequest.parse(value, owner: owner, identity: identity)); value.removeValue(forKey:"path")
        value["expectedBytes"] = true; XCTAssertThrowsError(try VMCheckpointRequest.parse(value, owner: owner, identity: identity)); value["expectedBytes"] = 4
        value["owner"] = UUID().uuidString; XCTAssertThrowsError(try VMCheckpointRequest.parse(value, owner: owner, identity: identity)); value["owner"] = owner.uuidString
        value["identity"] = ["engineSHA256":String(repeating:"f",count:64),"guestSHA256":identity.guestSHA256,"configurationSHA256":identity.configurationSHA256]
        XCTAssertThrowsError(try VMCheckpointRequest.parse(value, owner: owner, identity: identity))
    }
    func testParserRejectsOversizedChunkMissingGenerationAndFractionalOffset() {
        let owner=UUID(),tx=UUID()
        let oversized=Data(repeating:1,count:VMCheckpointStore.chunkBytes+1).base64EncodedString()
        XCTAssertThrowsError(try VMCheckpointRequest.parse(["owner":owner.uuidString,"action":"append","transaction":tx.uuidString,"offset":0,"base64":oversized],owner:owner,identity:identity))
        XCTAssertThrowsError(try VMCheckpointRequest.parse(["owner":owner.uuidString,"action":"append","transaction":tx.uuidString,"offset":0.5,"base64":"AA=="],owner:owner,identity:identity))
        XCTAssertThrowsError(try VMCheckpointRequest.parse(["owner":owner.uuidString,"action":"read","identity":identityBody,"offset":0,"length":1],owner:owner,identity:identity))
    }
    func testAuthorizationRequiresExactWebViewMainFrameAndOrigin() {
        let view=WKWebView(),other=WKWebView()
        XCTAssertTrue(VMCheckpointBridge.authorized(candidate:view,owned:view,isMainFrame:true,scheme:"orivyn-vm",host:"bundle",port:0))
        XCTAssertFalse(VMCheckpointBridge.authorized(candidate:other,owned:view,isMainFrame:true,scheme:"orivyn-vm",host:"bundle",port:0))
        XCTAssertFalse(VMCheckpointBridge.authorized(candidate:view,owned:view,isMainFrame:false,scheme:"orivyn-vm",host:"bundle",port:0))
        XCTAssertFalse(VMCheckpointBridge.authorized(candidate:view,owned:view,isMainFrame:true,scheme:"https",host:"bundle",port:0))
        XCTAssertFalse(VMCheckpointBridge.authorized(candidate:view,owned:view,isMainFrame:true,scheme:"orivyn-vm",host:"bundle",port:443))
    }
    func testBridgeOwnsTransactionAndInvalidationAbortsIt() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try VMCheckpointStore(root:root),owner=UUID()
        let bridge=VMCheckpointBridge(owner:owner,identity:identity,store:store)
        let begun=try await bridge.process(["owner":owner.uuidString,"action":"begin","identity":identityBody,"expectedBytes":4]) as? [String:Any]
        let text=try XCTUnwrap(begun?["transaction"] as? String)
        do { _ = try await bridge.process(["owner":owner.uuidString,"action":"append","transaction":UUID().uuidString,"offset":0,"base64":"AQIDBA=="]); XCTFail("Other transaction admitted") } catch {}
        let cleanup=bridge.invalidate(); await cleanup.value
        do { _ = try await bridge.process(["owner":owner.uuidString,"action":"append","transaction":text,"offset":0,"base64":"AQIDBA=="]); XCTFail("Invalidated bridge admitted work") } catch {}
        let next=try await store.begin(identity:identity,expectedBytes:1); try await store.abort(transaction:next)
    }
    func testReadRequiresLatestVerifiedGenerationAndReturnsCanonicalBase64() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try VMCheckpointStore(root:root),owner=UUID()
        let id=try await store.begin(identity:identity,expectedBytes:3)
        _ = try await store.append(transaction:id,offset:0,data:Data([1,2,3]))
        let saved=try await store.commit(transaction:id)
        let bridge=VMCheckpointBridge(owner:owner,identity:identity,store:store)
        let read:[String:Any]=["owner":owner.uuidString,"action":"read","identity":identityBody,"generation":saved.generation.uuidString,"offset":0,"length":3]
        do { _ = try await bridge.process(read); XCTFail("Read before verified latest admitted") } catch {}
        let latest=try await bridge.process(["owner":owner.uuidString,"action":"latest","identity":identityBody]) as? [String:Any]
        XCTAssertEqual(latest?["generation"] as? String,saved.generation.uuidString)
        let result=try await bridge.process(read) as? [String:Any]
        XCTAssertEqual(result?["base64"] as? String,"AQID")
        await bridge.invalidate().value
    }

    func testInvalidationDrainsConcurrentBeginBeforeStoreReuse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root)
        for _ in 0..<32 {
            let owner = UUID()
            let bridge = VMCheckpointBridge(owner: owner, identity: identity, store: store)
            let request: [String: Any] = ["owner": owner.uuidString, "action": "begin", "identity": identityBody, "expectedBytes": 3]
            let pending = Task { @MainActor in
                do { _ = try await bridge.process(request) } catch {}
            }
            await Task.yield()
            await bridge.invalidate().value
            // Drain must cover even a begin whose transaction was not yet returned.
            let next = try await store.begin(identity: identity, expectedBytes: 1)
            try await store.abort(transaction: next)
            await pending.value
        }
    }

    func testInvalidationDrainsCommitBeforeNextPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try VMCheckpointStore(root: root), owner = UUID()
        let bridge = VMCheckpointBridge(owner: owner, identity: identity, store: store)
        let begun = try await bridge.process(["owner": owner.uuidString, "action": "begin", "identity": identityBody, "expectedBytes": 3]) as? [String: Any]
        let transaction = try XCTUnwrap(begun?["transaction"] as? String)
        _ = try await bridge.process(["owner": owner.uuidString, "action": "append", "transaction": transaction, "offset": 0, "base64": "AQID"])
        let pending = Task { @MainActor in
            do { _ = try await bridge.process(["owner": owner.uuidString, "action": "commit", "transaction": transaction]) } catch {}
        }
        await Task.yield()
        await bridge.invalidate().value
        let next = try await store.begin(identity: identity, expectedBytes: 1)
        _ = try await store.append(transaction: next, offset: 0, data: Data([9]))
        let saved = try await store.commit(transaction: next)
        await pending.value
        let latest = try await store.latest(identity: identity)
        XCTAssertEqual(latest?.generation, saved.generation)
    }

}
