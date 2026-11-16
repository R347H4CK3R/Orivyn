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
        let data = try exportData([
            "a": exportedNode("a", text: "I like trains"),
            "b": exportedNode("b", parent: "a", text: "Noted", role: "assistant"),
            "c": exportedNode("c", parent: "b", text: "secret tool output", role: "tool")
        ], current: "c")
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
            let item: [String: Any] = ["title": "Chat \(n)", "ignored": String(repeating: "x", count: 200_000), "current_node": "m", "mapping": ["m": ["parent": NSNull(), "message": ["author": ["role":"user"], "content": ["content_type":"text", "parts":["Train \(n)"]]]]]]
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


    private func exportedNode(_ id: String, parent: Any = NSNull(), text: String, role: String = "user", type: String = "text", extraMessage: [String: Any] = [:]) -> [String: Any] {
        var message: [String: Any] = ["author": ["role": role], "content": ["content_type": type, "parts": [text]]]
        for (key, value) in extraMessage { message[key] = value }
        return ["id": id, "parent": parent, "message": message]
    }
    private func exportData(_ mapping: [String: Any], current: String? = nil, extra: [String: Any] = [:]) throws -> Data {
        var conversation: [String: Any] = ["title": "Synthetic tree", "mapping": mapping]
        if let current { conversation["current_node"] = current }
        for (key, value) in extra { conversation[key] = value }
        return try JSONSerialization.data(withJSONObject: [conversation])
    }
    func testSelectedBranchUsesParentAncestryNotTimestampsOrAbandonedSiblings() throws {
        let mapping: [String: Any] = [
            "root": ["id": "root", "parent": NSNull(), "message": NSNull()],
            "question": exportedNode("question", parent: "root", text: "Original question", extraMessage: ["create_time": 999]),
            "abandoned": exportedNode("abandoned", parent: "question", text: "Abandoned response", role: "assistant"),
            "chosen": exportedNode("chosen", parent: "question", text: "Selected response", role: "assistant", extraMessage: ["create_time": 1])]
        let notes = try FolderMemoryImport.chatGPT(exportData(mapping, current: "chosen"))
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes[0].content.contains("user: Original question"))
        XCTAssertTrue(notes[1].content.contains("assistant: Selected response"))
        XCTAssertFalse(notes.contains { $0.content.contains("Abandoned") })
        XCTAssertTrue(notes.allSatisfy { $0.content.contains("Synthetic tree") })
    }
    func testRejectsMissingCurrentNodeMissingParentsAndCycles() throws {
        let root = exportedNode("a", text: "Never partially imported")
        let cases = [try exportData(["a": root]),
                     try exportData(["a": root], current: "missing"),
                     try exportData(["a": exportedNode("a", parent: "missing", text: "x")], current: "a"),
                     try exportData(["a": exportedNode("a", parent: "b", text: "x"), "b": exportedNode("b", parent: "a", text: "y")], current: "a")]
        for data in cases { XCTAssertThrowsError(try FolderMemoryImport.chatGPT(data)) }
    }
    func testDoNotRememberConversationIsSkipped() throws {
        let data = try exportData(["a": exportedNode("a", text: "Do not import")], current: "a", extra: ["is_do_not_remember": true])
        XCTAssertTrue(try FolderMemoryImport.chatGPT(data).isEmpty)
    }
    func testHiddenReasoningAndToolDirectedMessagesAreNotMemories() throws {
        let entries: [(String, [String: Any])] = [
            ("a", ["metadata": ["is_visually_hidden_from_conversation": true]]),
            ("b", ["channel": "analysis"]),
            ("c", ["channel": "commentary", "recipient": "browser"]),
            ("d", ["is_do_not_remember": true]),
            ("e", ["metadata": ["is_do_not_remember": true]]),
            ("f", ["channel": "final", "recipient": "all"])]
        var mapping: [String: Any] = [:]; var parent: Any = NSNull()
        for (id, extra) in entries { mapping[id] = exportedNode(id, parent: parent, text: "message \(id)", role: "assistant", extraMessage: extra); parent = id }
        let notes = try FolderMemoryImport.chatGPT(exportData(mapping, current: "f"))
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].content.contains("assistant: message f"))
    }
    func testMultimodalMessageIncludesOnlyStringTextParts() throws {
        var node = exportedNode("a", text: "unused")
        node["message"] = ["author": ["role": "user"], "content": ["content_type": "multimodal_text", "parts": ["Describe this", ["content_type": "image_asset_pointer", "asset_pointer": "private-image"], "Use short sentences"]]]
        let notes = try FolderMemoryImport.chatGPT(exportData(["a": node], current: "a"))
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.content.contains("user: Describe this\nUse short sentences"), true)
        XCTAssertEqual(notes.first?.content.contains("private-image"), false)
    }
}
