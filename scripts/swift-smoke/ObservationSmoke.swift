import Foundation

/// Executable checks against real production Observable stores, not XCTest or UI tests.
@main struct ObservationSmoke {
    enum Failure: Error { case assertion(String) }
    @MainActor static var checks = 0
    @MainActor static func require(_ value: Bool, _ name: String) throws {
        guard value else { throw Failure.assertion(name) }
        checks += 1; print("PASS: \(name)")
    }
    @MainActor static func rejects(_ name: String, _ action: () throws -> Void) throws {
        do { try action() } catch { checks += 1; print("PASS: \(name)"); return }
        throw Failure.assertion(name)
    }
    @MainActor static func main() throws {
        let suite = "Orivyn.StaticSmoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.assertion("defaults available") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceStore(defaults: defaults)
        let project = try workspace.addProject(name: "  Research  ")
        let chat = UUID(), attachment = UUID()
        try workspace.assign(chat, to: project.id)
        try workspace.togglePin(chat); try workspace.toggleFavorite(attachment)
        let reopened = WorkspaceStore(defaults: defaults)
        try require(reopened.projects.first?.name == "Research", "project metadata roundtrip")
        try require(reopened.projectID(for: chat) == project.id, "project membership roundtrip")
        try require(reopened.isPinned(chat) && reopened.isFavorite(attachment), "pins and favorites roundtrip")
        try reopened.deleteProject(project.id)
        try require(reopened.projects.isEmpty && reopened.projectID(for: chat) == nil && reopened.isPinned(chat), "project deletion preserves unrelated pins")
        try rejects("blank project rejected") { _ = try reopened.addProject(name: " \n ") }
        var behavior = ResponseBehavior(); behavior.instructions = "Use Spanish."; behavior.warmth = 2
        try reopened.saveBehavior(behavior)
        try require(WorkspaceStore(defaults: defaults).behavior.instructions == "Use Spanish.", "behavior persisted")
        behavior.instructions = String(repeating: "😀", count: 129)
        try rejects("oversized behavior rejected") { try reopened.saveBehavior(behavior) }
        try require(reopened.behavior.instructions == "Use Spanish.", "rejected behavior leaves original")
        let corrupt = Data([0xff, 0, 0xaa]); defaults.set(corrupt, forKey: WorkspaceStore.storageKey)
        let blocked = WorkspaceStore(defaults: defaults)
        try require(blocked.loadError != nil, "corrupt workspace reported")
        try rejects("corrupt workspace blocks writes") { _ = try blocked.addProject(name: "Do not overwrite") }
        try require(defaults.data(forKey: WorkspaceStore.storageKey) == corrupt, "corrupt snapshot retained")

        let directory = root.appendingPathComponent("journal")
        let journal = try PluginJournal(directory: directory)
        let id = try journal.begin(connectionID: UUID(), toolName: "workspace.write")
        try require(journal.records.first?.id == id && journal.records.first?.state == .running, "write-ahead record exists")
        let recovered = try PluginJournal(directory: directory)
        try require(recovered.records.first?.state == .unknown, "interrupted call reopens unknown")
        try rejects("unknown call cannot gain invented success") { try recovered.finish(id: id, state: .serverReportedSuccess) }
        let success = try recovered.begin(connectionID: UUID(), toolName: "read")
        try recovered.finish(id: success, state: .serverReportedSuccess)
        let failure = try recovered.begin(connectionID: UUID(), toolName: "read")
        try recovered.finish(id: failure, state: .serverReportedError)
        let outcomes = try PluginJournal(directory: directory)
        try require(outcomes.records.first(where: { $0.id == success })?.state == .serverReportedSuccess && outcomes.records.first(where: { $0.id == failure })?.state == .serverReportedError, "confirmed outcome distinction persisted")
        for _ in 0..<105 {
            let call = try outcomes.begin(connectionID: UUID(), toolName: "read")
            try outcomes.finish(id: call, state: .serverReportedSuccess)
        }
        try require(outcomes.records.count == 100 && outcomes.records.contains(where: { $0.id == id && $0.state == .unknown }), "bounded history retains unresolved outcome")
        let file = directory.appendingPathComponent("plugin-executions.json")
        let bytes = Data("{ broken journal".utf8); try bytes.write(to: file)
        try rejects("corrupt journal rejected") { _ = try PluginJournal(directory: directory) }
        try require(try Data(contentsOf: file) == bytes, "corrupt journal bytes preserved")
        let failureDirectory = root.appendingPathComponent("write-failure")
        let failedJournal = try PluginJournal(directory: failureDirectory)
        let pending = try failedJournal.begin(connectionID: UUID(), toolName: "write")
        let savedDirectory = root.appendingPathComponent("preserved-journal")
        try FileManager.default.moveItem(at: failureDirectory, to: savedDirectory)
        try Data("Not a directory".utf8).write(to: failureDirectory)
        try rejects("failed outcome write reports failure") { try failedJournal.finish(id: pending, state: .serverReportedSuccess) }
        try require(failedJournal.requiresRecovery && failedJournal.records.first?.state == .unknown, "failed outcome blocks dispatch and becomes unknown")
        try rejects("new dispatch blocked until recovery") { _ = try failedJournal.begin(connectionID: UUID(), toolName: "write") }
        try FileManager.default.removeItem(at: failureDirectory)
        try FileManager.default.moveItem(at: savedDirectory, to: failureDirectory)
        try require(try PluginJournal(directory: failureDirectory).records.first?.state == .unknown, "restored durable running record recovers unknown")

        let full = try PluginJournal(directory: root.appendingPathComponent("unresolved-capacity"))
        for _ in 0..<100 { _ = try full.begin(connectionID: UUID(), toolName: "write") }
        try rejects("full unresolved journal cannot discard prior calls") { _ = try full.begin(connectionID: UUID(), toolName: "write") }
        try require(full.records.count == 100 && full.records.allSatisfy { $0.state == .running }, "capacity failure preserves all unresolved records")

        print("OBSERVATION_SMOKE_CHECKS_PASSED=\(checks)")
        print("Actual production logic; Linux static runtime only. iOS UI/file protection not verified.")
    }
}
