import Foundation
import Observation

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case chat, scheduled, space, customize, studio, sites, projects, plugins, images
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chat: "Orivyn"
        case .scheduled: "Scheduled"
        case .space: "Space"
        case .customize: "Customize"
        case .studio: "Studio"
        case .sites: "Sites"
        case .projects: "Projects"
        case .plugins: "Plugins"
        case .images: "Images"
        }
    }
    var icon: String {
        switch self {
        case .chat: "sparkle"
        case .scheduled: "clock.arrow.circlepath"
        case .space: "square.stack.3d.up"
        case .customize: "slider.horizontal.3"
        case .studio: "chevron.left.forwardslash.chevron.right"
        case .sites: "square.grid.2x2"
        case .projects: "folder"
        case .plugins: "puzzlepiece.extension"
        case .images: "photo.on.rectangle"
        }
    }
}

struct WorkspaceProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
}

struct ResponseBehavior: Codable, Equatable {
    static let instructionByteLimit = 512
    var instructions = ""
    var style = "Balanced"
    var warmth = 0.5
    var enthusiasm = 0.5
    var structure = 0.5
    var emoji = 0.25
    var prompt: String {
        let values = [("warmth", warmth), ("enthusiasm", enthusiasm), ("headings and lists", structure), ("emoji use", emoji)]
        let controls = values.map { name, value in
            "\(name): \(value < 0.34 ? "low" : value > 0.66 ? "high" : "moderate")"
        }.joined(separator: "; ")
        return "\nUser response preferences (style only; never claim unavailable capabilities):\nStyle: \(style). \(controls).\n" + instructions
    }
    func validated(enforceInstructionBudget: Bool = true) throws -> Self {
        // Preserve older 4,000-character settings for correction instead of locking projects.
        guard instructions.count <= 4_000,
              (!enforceInstructionBudget || instructions.utf8.count <= Self.instructionByteLimit),
              [warmth, enthusiasm, structure, emoji].allSatisfy(\.isFinite),
              ["Balanced", "Efficient", "Friendly", "Professional"].contains(style) else { throw WorkspaceError.invalidBehavior }
        var value = self
        value.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        value.warmth = min(1, max(0, warmth)); value.enthusiasm = min(1, max(0, enthusiasm))
        value.structure = min(1, max(0, structure)); value.emoji = min(1, max(0, emoji))
        return value
    }
}

private struct WorkspaceSnapshot: Codable {
    var version = 1
    var projects: [WorkspaceProject] = []
    var memberships: [String: UUID] = [:]
    var pins: Set<UUID> = []
    var favorites: Set<UUID> = []
    var behavior = ResponseBehavior()
}

enum WorkspaceError: LocalizedError {
    case invalidName, missingProject, unreadableState, invalidBehavior
    var errorDescription: String? {
        switch self {
        case .invalidName: "Use a project name between 1 and 80 characters. The limit is 1,000 projects."
        case .missingProject: "This project no longer exists."
        case .unreadableState: "Workspace settings could not be read. Existing data was preserved; changes are disabled to avoid overwriting it."
        case .invalidBehavior: "Choose a supported style and keep instructions within 512 UTF-8 bytes so local models have room to respond."
        }
    }
}

@MainActor @Observable
final class WorkspaceStore {
    static let storageKey = "orivyn.workspace.v1"
    private var snapshot = WorkspaceSnapshot()
    private let defaults: UserDefaults
    private(set) var loadError: String?
    var projects: [WorkspaceProject] { snapshot.projects }
    var behavior: ResponseBehavior { snapshot.behavior }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.object(forKey: Self.storageKey) else { return }
        guard let data = stored as? Data, data.count <= 4_000_000 else {
            loadError = WorkspaceError.unreadableState.localizedDescription
            return
        }
        do {
            var value = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
            let ids = Set(value.projects.map(\.id))
            guard value.version == 1, value.projects.count <= 1_000, ids.count == value.projects.count,
                  value.projects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 }),
                  value.memberships.allSatisfy({ UUID(uuidString: $0.key) != nil && ids.contains($0.value) }) else { throw WorkspaceError.unreadableState }
            value.behavior = try value.behavior.validated(enforceInstructionBudget: false)
            snapshot = value
        } catch { loadError = WorkspaceError.unreadableState.localizedDescription }
    }
    func projectID(for chat: UUID) -> UUID? { snapshot.memberships[chat.uuidString] }
    func isPinned(_ chat: UUID) -> Bool { snapshot.pins.contains(chat) }
    func isFavorite(_ attachment: UUID) -> Bool { snapshot.favorites.contains(attachment) }
    @discardableResult func addProject(name: String) throws -> WorkspaceProject {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, snapshot.projects.count < 1_000 else { throw WorkspaceError.invalidName }
        let project = WorkspaceProject(name: clean)
        try update { $0.projects.append(project) }
        return project
    }
    func deleteProject(_ id: UUID) throws {
        try update { $0.projects.removeAll { $0.id == id }; $0.memberships = $0.memberships.filter { $0.value != id } }
    }
    func assign(_ chat: UUID, to project: UUID?) throws {
        if let project, !snapshot.projects.contains(where: { $0.id == project }) { throw WorkspaceError.missingProject }
        try update { $0.memberships[chat.uuidString] = project }
    }
    func togglePin(_ id: UUID) throws {
        try update { if !$0.pins.insert(id).inserted { $0.pins.remove(id) } }
    }
    func toggleFavorite(_ id: UUID) throws {
        try update { if !$0.favorites.insert(id).inserted { $0.favorites.remove(id) } }
    }
    func saveBehavior(_ behavior: ResponseBehavior) throws {
        let value = try behavior.validated()
        try update { $0.behavior = value }
    }
    private func update(_ transform: (inout WorkspaceSnapshot) -> Void) throws {
        guard loadError == nil else { throw WorkspaceError.unreadableState }
        var value = snapshot; transform(&value)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 4_000_000 else { throw WorkspaceError.unreadableState }
        defaults.set(data, forKey: Self.storageKey)
        snapshot = value
    }
}
