import XCTest
import CryptoKit
@testable import OrivynVMProof

final class VMPolicyTests: XCTestCase {
    func testOnlyPinnedGuestMayExceedSmallAssetLimit() {
        let disk = VMAsset(name: "maintained.img", bytes: 135266304, sha256: "c318b702448a2f08400321446719af10568a9ef878a5fe898c1cb815c1bebe72", mime: "application/octet-stream")
        XCTAssertTrue(VMAssetStore.acceptedSize(disk))
        XCTAssertFalse(VMAssetStore.acceptedSize(VMAsset(name: "other.img", bytes: disk.bytes, sha256: disk.sha256, mime: disk.mime)))
        XCTAssertFalse(VMAssetStore.acceptedSize(VMAsset(name: disk.name, bytes: disk.bytes, sha256: String(repeating: "0", count: 64), mime: disk.mime)))
        XCTAssertFalse(VMAssetStore.acceptedSize(VMAsset(name: disk.name, bytes: disk.bytes + 1, sha256: disk.sha256, mime: disk.mime)))
    }
    func testOnlyExactAssetRoutesAndGETAreAdmitted() {
        for file in VMAssetCatalog.files {
            XCTAssertEqual(VMAssetStore.allowedPath(URLRequest(url: URL(string: "orivyn-vm://bundle/" + file.name)!)), "/" + file.name)
        }
        for address in ["https://example.com/index.html", "http://bundle/index.html", "file:///index.html", "orivyn-vm://other/index.html", "orivyn-vm://bundle:443/index.html", "orivyn-vm://user@bundle/index.html", "orivyn-vm://bundle/index.html?q=1", "orivyn-vm://bundle/%69ndex.html", "orivyn-vm://bundle/../index.html", "orivyn-vm://bundle/missing", "orivyn-vm://bundle/controller.js#x"] {
            XCTAssertNil(VMAssetStore.allowedPath(URLRequest(url: URL(string: address)!)), address)
        }
        var post = URLRequest(url: URL(string: "orivyn-vm://bundle/index.html")!); post.httpMethod = "POST"
        XCTAssertNil(VMAssetStore.allowedPath(post))
    }
    func testBundledBytesMatchPinnedManifest() throws {
        let store = try VMAssetStore(root: Bundle.main.resourceURL!.appendingPathComponent("Assets"))
        for file in VMAssetCatalog.files {
            let result = try store.response(for: URLRequest(url: URL(string: "orivyn-vm://bundle/" + file.name)!))
            XCTAssertEqual(result.0.count, file.bytes); XCTAssertEqual(result.1, file.mime)
        }
    }
    func testCorruptOversizedAndSymlinkInputsAreRefusedBeforeWebView() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("index.html"); let bytes = Data([1, 2, 3])
        let item = VMAsset(name: "index.html", bytes: bytes.count, sha256: SHA256.hash(data: bytes).map{String(format:"%02x",$0)}.joined(), mime:"text/html")
        try bytes.write(to: file); XCTAssertNoThrow(try VMAssetStore(root: root, catalog: [item]))
        try Data([3, 2, 1]).write(to: file); XCTAssertThrowsError(try VMAssetStore(root: root, catalog: [item]))
        try Data([1, 2, 3, 4]).write(to: file); XCTAssertThrowsError(try VMAssetStore(root: root, catalog: [item]))
        try FileManager.default.removeItem(at: file)
        let outside = root.appendingPathComponent("outside"); try bytes.write(to: outside)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        XCTAssertThrowsError(try VMAssetStore(root: root, catalog: [item]))
        XCTAssertThrowsError(try VMAssetStore(root: root, catalog: [VMAsset(name:"../outside",bytes:3,sha256:item.sha256,mime:item.mime)]))
    }
    func testImmutableAssetBytesDoNotFollowLaterDiskReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("index.html"); let bytes = Data([1, 2, 3]); try bytes.write(to:file)
        let item = VMAsset(name:"index.html",bytes:3,sha256:SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),mime:"text/html")
        let store = try VMAssetStore(root:root,catalog:[item]); try Data([9,9,9]).write(to:file)
        XCTAssertEqual(try store.response(for:URLRequest(url:URL(string:"orivyn-vm://bundle/index.html")!)).0,bytes)
    }
    func testDiagnosticIsBoundedAndCannotPretendExecution() {
        let owner = UUID()
        var value:[String:Any] = ["version":1,"owner":owner.uuidString,"event":"diagnostic","instructions":0,"diagnostic":"primary WebAssembly: CompileError"]
        XCTAssertNotNil(VMStatus.parse(value,owner:owner))
        value["diagnostic"] = String(repeating:"x",count:257); XCTAssertNil(VMStatus.parse(value,owner:owner))
        value["diagnostic"] = "test";value["instructions"] = 1;XCTAssertNil(VMStatus.parse(value,owner:owner))
        value["instructions"] = 0;value["event"] = "running";XCTAssertNil(VMStatus.parse(value,owner:owner))
    }
    func testStatusRequiresExactCurrentOwnerAndBoundedSchema() {
        let owner = UUID()
        let valid:[String:Any] = ["version":1,"owner":owner.uuidString,"event":"running","instructions":123]
        XCTAssertEqual(VMStatus.parse(valid, owner:owner)?.instructions,123)
        XCTAssertNil(VMStatus.parse(valid,owner:UUID()))
        for (key,value) in [("version",true as Any),("instructions",true as Any),("instructions",-1 as Any),("instructions",Double.infinity as Any),("instructions",1.5 as Any),("event","execute" as Any),("extra","payload" as Any)] {
            var changed=valid;changed[key]=value;XCTAssertNil(VMStatus.parse(changed,owner:owner))
        }
    }
}

@MainActor
final class VMDelegateRegistrationTests: XCTestCase {
    func testPolicyCallbacksAreRegisteredWithObjectiveCRuntime() {
        let controller = VMHarnessController()
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationResponse:decisionHandler:")))
    }
}
