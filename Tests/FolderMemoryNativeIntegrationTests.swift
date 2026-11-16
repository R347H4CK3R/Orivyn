import XCTest
@testable import JarvisEVO

/// Actual coordinated Darwin reader + AppModel + SQLite; synthetic local folder.
/// Does not assert an external Files provider granted access.
@MainActor
final class FolderMemoryNativeIntegrationTests: XCTestCase {
    func testReviewThenImportAndRepeatPreservesDraftAndOriginalMemory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Export")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "FolderMemory." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try Data("Train travel preference".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("data.sqlite"))
        let original = MemoryNote(content: "Keep original")
        try await store.saveMemory(original)
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        model.draft = "Keep my unsent draft"
        let preview = try await FolderMemoryReader.read(folder) { _ in }
        XCTAssertEqual(preview.notes.count, 1)
        let before = try await store.memories()
        XCTAssertEqual(before, [original], "Reading/preview must never save automatically")
        let saved = await model.importFolderMemories(preview.notes)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.draft, "Keep my unsent draft")
        let repeated = await model.importFolderMemories(preview.notes)
        XCTAssertTrue(repeated)
        XCTAssertEqual(model.memories.count, 2)
        XCTAssertTrue(model.memories.contains(original))
        XCTAssertNil(model.errorMessage)
    }
}
