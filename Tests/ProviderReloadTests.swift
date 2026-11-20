import XCTest
@testable import JarvisEVO

/// Native integration gate: no model inference is claimed by these metadata fixtures.
@MainActor final class ProviderReloadTests: XCTestCase {
    func testReloadReplacesChangedDescriptorAndPrunesRemovedProvider() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modelsRoot = root.appendingPathComponent("Models")
        let suite = "OrivynProviderReload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let models = try LocalModelStore(root: modelsRoot)
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let app = AppModel(offlineAutoSelection: false, store: store, attachmentService: attachments, modelStore: models, defaults: defaults)
        let first = LocalModelDescriptor(id: "test", name: "Old", fileName: "test.gguf",
            downloadURL: nil, sha256: String(repeating: "a", count: 64), byteCount: 24,
            license: "Test fixture", sourceURL: nil)
        let changed = LocalModelDescriptor(id: "test", name: "Updated", fileName: "new.gguf",
            downloadURL: nil, sha256: String(repeating: "b", count: 64), byteCount: 32,
            license: "Test fixture", sourceURL: nil)
        let manifest = modelsRoot.appendingPathComponent("installed-models.json")
        try Data(repeating: 0, count: 24).write(to: modelsRoot.appendingPathComponent(first.fileName))
        try JSONEncoder().encode([first]).write(to: manifest, options: .atomic)
        try await app.reloadProviders()
        app.selectedProviderID = first.id
        XCTAssertEqual(app.selectedLocalAgentProvider?.model, first)
        let engine = try XCTUnwrap(app.selectedLocalAgentProvider?.engine)
        try Data(repeating: 0, count: 32).write(to: modelsRoot.appendingPathComponent(changed.fileName))
        try JSONEncoder().encode([changed]).write(to: manifest, options: .atomic)
        try await app.reloadProviders()
        XCTAssertEqual(app.selectedLocalAgentProvider?.model, changed)
        XCTAssertTrue(app.selectedLocalAgentProvider?.engine === engine)
        try JSONEncoder().encode([LocalModelDescriptor]()).write(to: manifest, options: .atomic)
        try await app.reloadProviders()
        app.selectedProviderID = first.id
        XCTAssertNil(app.selectedLocalAgentProvider)
    }
}
