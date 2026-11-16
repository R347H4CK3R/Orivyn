import XCTest
@testable import JarvisEVO

final class FolderMemoryImportTests: XCTestCase {
    func testTextSplitsWithoutLossAndDeduplicates() throws {
        let text = String(repeating: "café 🐈 ", count: 1000)
        let notes = try FolderMemoryImport.notes(text: text, source: "notes.txt")
        XCTAssertGreaterThan(notes.count, 1)
        XCTAssertTrue(notes.allSatisfy { $0.content.count <= 4000 && $0.content.utf8.count <= 32768 })
        XCTAssertEqual(notes.map { String($0.content[$0.content.index(after: $0.content.firstIndex(of: "\n")!)...]) }.joined(), text)
        XCTAssertEqual(FolderMemoryImport.additions(notes, existing: notes).count, 0)
    }
    func testChatGPTExtractsTextWithRoleAndTitleNotHiddenTools() throws {
        let data = Data(#"[{"title":"Trip","mapping":{"a":{"message":{"author":{"role":"user"},"create_time":1,"content":{"content_type":"text","parts":["I like trains"]}}},"b":{"message":{"author":{"role":"assistant"},"create_time":2,"content":{"content_type":"text","parts":["Noted"]}}},"c":{"message":{"author":{"role":"tool"},"content":{"parts":["secret tool output"]}}}}}]"#.utf8)
        let notes = try FolderMemoryImport.chatGPT(data)
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes[0].content.contains("user: I like trains"))
        XCTAssertTrue(notes[1].content.contains("assistant: Noted"))
        XCTAssertFalse(notes.contains { $0.content.contains("secret tool output") })
    }
    func testFolderSkipsBinaryAndSymlinkAndDoesNotMutateSources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("remember trains".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try Data([0,1,2]).write(to: root.appendingPathComponent("movie.mp4"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("linked.txt").path, withDestinationPath: "/etc/passwd")
        let review = try FolderMemoryImport.scan(root)
        XCTAssertEqual(review.notes.count, 1)
        XCTAssertEqual(review.skipped, 2)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8), "remember trains")
    }
    func testMalformedJSONAndNonUTF8AreReportedNotImported() throws {
        XCTAssertThrowsError(try FolderMemoryImport.chatGPT(Data("bad".utf8)))
        XCTAssertThrowsError(try FolderMemoryImport.chatGPT(Data("{}".utf8)))
    }
    func testOversizedEligibleFileStopsWholePreview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(FolderMemoryImport.fileLimit + 1)); try handle.close()
        XCTAssertThrowsError(try FolderMemoryImport.scan(root))
    }
    func testCredentialAndInvalidUTF8FilesAreSkipped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([255]).write(to: root.appendingPathComponent("invalid.txt"))
        try Data("not imported".utf8).write(to: root.appendingPathComponent("passwords.txt"))
        let review = try FolderMemoryImport.scan(root)
        XCTAssertTrue(review.notes.isEmpty)
        XCTAssertEqual(review.skipped, 2)
        XCTAssertEqual(review.issueCount, 2)
    }
    func testPathWithSpacesAndUnicodeAndNestedSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Café notes"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Train preference".utf8).write(to: root.appendingPathComponent("Café notes/a.md"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside").path, withDestinationPath: "/etc")
        let review = try FolderMemoryImport.scan(root)
        XCTAssertEqual(review.notes.count, 1)
        XCTAssertTrue(review.notes[0].content.contains("Café notes/a.md"))
        XCTAssertEqual(review.skipped, 1)
    }

    func testStreamingChatGPTReadsMoreThanPerFileLimitWithoutLoadingWholeArchive() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data("[".utf8))
        for n in 0..<90 {
            let item: [String: Any] = ["title": "Chat \(n)", "ignored": String(repeating: "x", count: 200_000), "mapping": ["m": ["message": ["author": ["role":"user"], "content": ["content_type":"text", "parts":["Train \(n)"]]]]]]
            if n > 0 { try writer.write(contentsOf: Data(",".utf8)) }
            try writer.write(contentsOf: JSONSerialization.data(withJSONObject: item))
        }
        try writer.write(contentsOf: Data("]".utf8)); try writer.close()
        let reader = try FileHandle(forReadingFrom: file); defer { try? reader.close() }
        let result = try FolderMemoryImport.streamChatGPT(reader)
        XCTAssertEqual(result.count, 90)
        XCTAssertTrue(result.last!.content.contains("Train 89"))
    }
    func testStreamingRejectsTruncatedOrTrailingCommaInsteadOfPartialImport() throws {
        for text in ["[{", "[{\"mapping\":{}},]", "[]garbage"] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data(text.utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let reader = try FileHandle(forReadingFrom: file); defer { try? reader.close() }
            XCTAssertThrowsError(try FolderMemoryImport.streamChatGPT(reader))
        }
    }

    func testScanCancellationLeavesSourceUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes.txt")
        try Data("Keep source".utf8).write(to: file)
        let work = Task {
            try FolderMemoryImport.scan(root) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        do { _ = try await work.value; XCTFail("Cancelled scan completed") } catch is CancellationError { }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Keep source")
    }
    func testCumulativeEntryNoteAndTextLimitsAbortInsteadOfReturningPartialReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<3 { try Data("Note \(i)".utf8).write(to: root.appendingPathComponent("\(i).txt")) }
        XCTAssertThrowsError(try FolderMemoryImport.scan(root, limits: .init(entries: 2, notes: 10, textBytes: 1000)))
        XCTAssertThrowsError(try FolderMemoryImport.scan(root, limits: .init(entries: 10, notes: 2, textBytes: 1000)))
        XCTAssertThrowsError(try FolderMemoryImport.scan(root, limits: .init(entries: 10, notes: 10, textBytes: 60)))
    }

}
