import XCTest
@testable import JarvisEVO

final class ArchiveFormatReportTests: XCTestCase {
    typealias Report = ArchiveFormatReport
    private func file(_ path: String, _ bytes: Int64 = 0) -> Report.InputFile { .init(relativePath: path, bytes: bytes) }
    private func summary(_ paths: [String]) throws -> Report.Summary {
        try Report.summarize(files: paths.map { file($0) }, conversationCount: 2, messageCount: 3, unresolvedRecords: 4)
    }
    func testFixedCategoriesAndRootPresenceInStableOrder() throws {
        let paths = ["conversations.json", "conversations-0.json", "conversations-12.json", "chat.html", "index.html", "export_manifest.json", "conversation_asset_file_names.json", "library_files.json", "private/person.DAT", "photo.JPG", "other.bin"]
        let value = try summary(paths)
        XCTAssertEqual(value.retainedFiles, 11); XCTAssertEqual(value.datFiles, 1)
        XCTAssertEqual(value.supportedExtensionFiles, 7); XCTAssertEqual(value.otherFiles, 3)
        XCTAssertEqual(value.conversationCount, 2); XCTAssertEqual(value.messageCount, 3); XCTAssertEqual(value.unresolvedRecords, 4)
        XCTAssertEqual(value.numberedConversationFiles, 2)
        XCTAssertEqual(value.metadata, [.legacyConversations, .numberedConversations, .legacyViewer, .currentViewer, .exportManifest, .assetNames, .libraryFiles])
        XCTAssertEqual(try summary(paths.reversed()), value)
    }
    func testNestedAndDeceptiveNamesDoNotClaimMetadataPresence() throws {
        let value = try summary(["nested/conversations.json", "nested/chat.html", "nested/index.html", "Conversations.json", "conversations-.json", "conversations-x.json", "conversations-١.json", "conversations-1.json.bak", "conversations_1.json", "secret-name.txt", "secret-id.dat"])
        XCTAssertEqual(value.metadata, []); XCTAssertEqual(value.numberedConversationFiles, 0)
        XCTAssertEqual(value.retainedFiles, 11)
        let display = String(reflecting: value)
        XCTAssertFalse(display.contains("secret-name")); XCTAssertFalse(display.contains("secret-id")); XCTAssertFalse(display.contains("nested"))
        XCTAssertEqual(Set(Report.Metadata.allCases.map(\.rawValue)).count, 7)
        XCTAssertEqual(Report.Metadata.allCases.map(\.label), ["Single conversation JSON present", "Numbered conversation JSON present", "Legacy viewer present", "Current viewer present", "Export manifest present", "Asset-name metadata present", "Library metadata present"])
        XCTAssertEqual(Set(Mirror(reflecting: value).children.compactMap(\.label)), Set(["retainedFiles", "datFiles", "supportedExtensionFiles", "otherFiles", "conversationCount", "messageCount", "unresolvedRecords", "metadata", "numberedConversationFiles"]))
    }
    func testRejectsUnsafeDuplicateAndOversizedPaths() throws {
        for path in ["", "/absolute", "a//b", "a/../b", "a/./b", "a\\b", "a\n", "a:b", String(repeating: "a/", count: 100_000), String(repeating: "x", count: 256)] {
            XCTAssertThrowsError(try summary([path]), "Unsafe path must reject")
        }
        XCTAssertThrowsError(try summary(["same.txt", "same.txt"]))
        XCTAssertEqual(try summary(["100% notes.dat"]).datFiles, 1)
        XCTAssertEqual(try summary([Array(repeating: "a", count: 65).joined(separator: "/")]).otherFiles, 1)
        XCTAssertEqual(try summary(["a.txt", "A.txt"]).retainedFiles, 2, "Literal paths remain distinct")
    }
    func testNumericAndFileCountBounds() throws {
        for bytes: Int64 in [-1, .min] {
            XCTAssertThrowsError(try Report.summarize(files: [file("a.dat", bytes)], conversationCount: 0, messageCount: 0, unresolvedRecords: 0))
        }
        let boundary = try Report.summarize(files: [file("a.dat", .max)], conversationCount: 10_000, messageCount: 500_000, unresolvedRecords: 20_000)
        XCTAssertEqual(boundary.datFiles, 1)
        for counts in [(-1,0,0),(10_001,0,0),(0,-1,0),(0,500_001,0),(0,0,-1),(0,0,20_001),(Int.max,Int.max,Int.max)] {
            XCTAssertThrowsError(try Report.summarize(files: [], conversationCount: counts.0, messageCount: counts.1, unresolvedRecords: counts.2))
        }
        let files = (0..<20_000).map { file("file-\($0).dat") }
        XCTAssertEqual(try Report.summarize(files: files, conversationCount: 0, messageCount: 0, unresolvedRecords: 0).retainedFiles, 20_000)
        XCTAssertThrowsError(try Report.summarize(files: files + [file("extra")], conversationCount: 0, messageCount: 0, unresolvedRecords: 0))
    }
    func testAllSupportedExtensionsAreOnlyExtensionCounts() throws {
        let value = try summary(["a.txt", "b.JSON", "c.pdf", "d.png", "e.jpg", "f.jpeg", "g.heic", "h.heif", "i.dat", "j", "k.zip"])
        XCTAssertEqual(value.supportedExtensionFiles, 8); XCTAssertEqual(value.datFiles, 1); XCTAssertEqual(value.otherFiles, 2)
        XCTAssertTrue(value.metadata.isEmpty)
    }
}
