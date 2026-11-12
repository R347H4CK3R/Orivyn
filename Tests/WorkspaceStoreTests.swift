import XCTest
@testable import JarvisEVO

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "Orivyn.WorkspaceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testProjectMembershipPinsAndFavoritesSurviveRelaunch() throws {
        let store = WorkspaceStore(defaults: defaults)
        let project = try store.addProject(name: "  Research  ")
        let chat = UUID(), attachment = UUID()
        try store.assign(chat, to: project.id)
        try store.togglePin(chat); try store.toggleFavorite(attachment)
        let reloaded = WorkspaceStore(defaults: defaults)
        XCTAssertEqual(reloaded.projects.first?.name, "Research")
        XCTAssertEqual(reloaded.projectID(for: chat), project.id)
        XCTAssertTrue(reloaded.isPinned(chat)); XCTAssertTrue(reloaded.isFavorite(attachment))
    }
    func testDeletingProjectOnlyRemovesMembership() throws {
        let store = WorkspaceStore(defaults: defaults)
        let project = try store.addProject(name: "Planning"), chat = UUID()
        try store.assign(chat, to: project.id); try store.togglePin(chat)
        try store.deleteProject(project.id)
        XCTAssertNil(store.projectID(for: chat)); XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(store.isPinned(chat))
    }
    func testInvalidProjectInputDoesNotMutateState() throws {
        let store = WorkspaceStore(defaults: defaults)
        XCTAssertThrowsError(try store.addProject(name: " \n "))
        XCTAssertThrowsError(try store.addProject(name: String(repeating: "x", count: 81)))
        XCTAssertThrowsError(try store.assign(UUID(), to: UUID()))
        XCTAssertTrue(store.projects.isEmpty)
    }
    func testCorruptSnapshotIsPreservedAndWritesBlocked() {
        let original = Data([0xff, 0, 0xaa])
        defaults.set(original, forKey: WorkspaceStore.storageKey)
        let store = WorkspaceStore(defaults: defaults)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.addProject(name: "Do not overwrite"))
        XCTAssertEqual(defaults.data(forKey: WorkspaceStore.storageKey), original)
    }
    func testUnexpectedStoredTypeIsPreserved() {
        defaults.set("not a snapshot", forKey: WorkspaceStore.storageKey)
        let store = WorkspaceStore(defaults: defaults)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.addProject(name: "Do not overwrite"))
        XCTAssertEqual(defaults.string(forKey: WorkspaceStore.storageKey), "not a snapshot")
    }
    func testBehaviorRoundTripAndByteLimit() throws {
        let store = WorkspaceStore(defaults: defaults)
        var behavior = ResponseBehavior()
        behavior.instructions = "Use Spanish."; behavior.warmth = 2; behavior.enthusiasm = -1
        try store.saveBehavior(behavior)
        let reloaded = WorkspaceStore(defaults: defaults)
        XCTAssertEqual(reloaded.behavior.warmth, 1); XCTAssertEqual(reloaded.behavior.enthusiasm, 0)
        XCTAssertTrue(reloaded.behavior.prompt.contains("Use Spanish."))
        behavior.instructions = String(repeating: "😀", count: 129)
        XCTAssertThrowsError(try store.saveBehavior(behavior))
        XCTAssertEqual(store.behavior.instructions, "Use Spanish.")
    }
    func testLegacyOversizedInstructionsKeepProjectsEditableAndCanBeCorrected() throws {
        let store = WorkspaceStore(defaults: defaults)
        let project = try store.addProject(name: "Keep this project")
        let original = try replaceStoredBehavior(instructions: String(repeating: "x", count: 2_000), warmth: 12)
        let reloaded = WorkspaceStore(defaults: defaults)
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.projects.first?.id, project.id)
        XCTAssertEqual(reloaded.behavior.instructions.count, 2_000)
        XCTAssertEqual(reloaded.behavior.warmth, 1)
        XCTAssertEqual(defaults.data(forKey: WorkspaceStore.storageKey), original)
        XCTAssertNoThrow(try reloaded.addProject(name: "Still editable"))
        var correction = reloaded.behavior; correction.instructions = "Brief replies."
        try reloaded.saveBehavior(correction)
        XCTAssertEqual(WorkspaceStore(defaults: defaults).behavior.instructions, "Brief replies.")
    }
    private func replaceStoredBehavior(instructions: String, warmth: Double) throws -> Data {
        let stored = try XCTUnwrap(defaults.data(forKey: WorkspaceStore.storageKey))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        var behavior = try XCTUnwrap(object["behavior"] as? [String: Any])
        behavior["instructions"] = instructions; behavior["warmth"] = warmth; object["behavior"] = behavior
        let data = try JSONSerialization.data(withJSONObject: object)
        defaults.set(data, forKey: WorkspaceStore.storageKey)
        return data
    }
}
