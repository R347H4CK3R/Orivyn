import XCTest
@testable import JarvisEVO

final class LocalModelRemovalPlanTests: XCTestCase {
    private func model(_ id: String = "selected", file: String = "selected.gguf", hash: String = "a", name: String = "Original", bytes: Int64 = 10, license: String = "fixture", download: URL? = nil, source: URL? = nil) -> LocalModelDescriptor {
        LocalModelDescriptor(id: id, name: name, fileName: file, downloadURL: download, sha256: String(repeating: hash, count: 64), byteCount: bytes, license: license, sourceURL: source)
    }
    func testExactSelectionRemovesOnlySelectedAndPreservesOrderAndInput() throws {
        let a = model("a", file: "a.gguf"), b = model(), c = model("c", file: "c.gguf")
        let original = [a,b,c]
        XCTAssertEqual(try LocalModelRemovalPlan.updatedManifest(removing: b, from: original), [a,c])
        XCTAssertEqual(original, [a,b,c])
    }
    func testAbsentIDCannotAuthorizeFileRemoval() {
        XCTAssertThrowsError(try LocalModelRemovalPlan.updatedManifest(removing: model(), from: [])) {
            XCTAssertEqual($0 as? LocalModelRemovalPlanError, .staleDescriptor)
        }
    }
    func testEveryChangedDescriptorFieldIsStale() {
        let variants = [model(file: "replacement.gguf"), model(hash: "b"), model(name: "Replacement"), model(bytes: 20), model(license: "changed"), model(download: URL(string: "https://example.com/model")), model(source: URL(string: "https://example.com/source"))]
        for replacement in variants {
            XCTAssertThrowsError(try LocalModelRemovalPlan.updatedManifest(removing: model(), from: [replacement])) {
                XCTAssertEqual($0 as? LocalModelRemovalPlanError, .staleDescriptor)
            }
        }
    }
    func testDuplicateIDIsAmbiguousEvenWhenDescriptorsAreIdentical() {
        for entries in [[model(),model()], [model(),model(file: "other.gguf")]] {
            XCTAssertThrowsError(try LocalModelRemovalPlan.updatedManifest(removing: model(), from: entries)) {
                XCTAssertEqual($0 as? LocalModelRemovalPlanError, .ambiguousManifest)
            }
        }
    }
    func testSharedFilenameAcrossIDsCannotDeleteAnotherModelsFile() {
        XCTAssertThrowsError(try LocalModelRemovalPlan.updatedManifest(removing: model(), from: [model(), model("other")])) {
            XCTAssertEqual($0 as? LocalModelRemovalPlanError, .ambiguousManifest)
        }
    }
    func testErrorsDoNotIncludeDescriptorOrPathData() {
        for error in [LocalModelRemovalPlanError.staleDescriptor, .ambiguousManifest] {
            XCTAssertFalse(error.localizedDescription.contains("selected.gguf"))
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
