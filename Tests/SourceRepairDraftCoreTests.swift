import XCTest
import CryptoKit
@testable import JarvisEVO

@MainActor
final class SourceRepairDraftCoreTests: XCTestCase {
    func testLocalPreviewIsAnchoredToVerifiedOriginalAndNeverApplied() throws {
        let text = "let value = 1\n"
        var bytes = Data("blob \(text.utf8.count)\0".utf8); bytes.append(Data(text.utf8))
        let sha = Insecure.SHA1.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let file = RepositoryInspectionFile(path: "Core/App.swift", commitSHA: String(repeating: "a", count: 40), blobSHA: sha, text: text)
        let draft = try SourceRepairDraftCore().create(file: file, replacement: "let value = 2\n", summary: "Propose updated value")
        XCTAssertEqual(draft.status, "draftNotApplied")
        XCTAssertEqual(draft.blobSHA, sha)
        XCTAssertTrue(draft.diff.contains("-let value = 1"))
        XCTAssertTrue(draft.diff.contains("+let value = 2"))
        XCTAssertTrue(draft.patch.hasSuffix(draft.diff))
        XCTAssertTrue(draft.patch.contains("# Base blob: " + sha))
        XCTAssertTrue(draft.patch.contains("# Base commit: " + file.commitSHA))
        XCTAssertTrue(draft.patch.contains("not applied or tested"))
        XCTAssertTrue(draft.exportFilename.hasSuffix(".patch"))
        XCTAssertLessThanOrEqual(draft.patch.utf8.count, 310_000)
        let wrong = RepositoryInspectionFile(path: file.path, commitSHA: file.commitSHA, blobSHA: String(repeating: "b", count: 40), text: text)
        XCTAssertThrowsError(try SourceRepairDraftCore().create(file: wrong, replacement: "changed\n", summary: "Proposed edit"))
    }
}
