import Foundation
import Observation

/// Write-ahead outcome tracking. No credentials, arguments, result bodies or
/// conversation text are stored. Restart never replays an interrupted request.
@MainActor @Observable
final class PluginJournal {
    private struct Snapshot: Codable {
        var version = 1
        var records: [PluginExecutionRecord]
    }
    private let file: URL
    private(set) var records: [PluginExecutionRecord] = []
    init(directory: URL) throws {
        file = directory.appendingPathComponent("plugin-executions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, let size = values.fileSize, size <= 262_144 else {
                throw PluginExecutionError.invalidJournal
            }
            let decoded = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
            guard decoded.version == 1, decoded.records.count <= 100,
                  Set(decoded.records.map(\.id)).count == decoded.records.count,
                  decoded.records.allSatisfy({ PluginReviewGate.validName($0.toolName) && $0.createdAt.timeIntervalSince1970.isFinite }) else {
                throw PluginExecutionError.invalidJournal
            }
            var recovered = decoded.records
            for index in recovered.indices where recovered[index].state == .running { recovered[index].state = .unknown }
            if recovered.contains(where: { $0.state == .unknown }) { try save(recovered) }
            records = recovered
        } catch { throw PluginExecutionError.invalidJournal }
    }
    func begin(connectionID: UUID, toolName: String, now: Date = Date()) throws -> UUID {
        guard PluginReviewGate.validName(toolName), now.timeIntervalSince1970.isFinite else { throw PluginExecutionError.invalidReview }
        var next = records
        if next.count >= 100 {
            guard let oldest = next.indices.reversed().first(where: {
                next[$0].state != .running && next[$0].state != .unknown
            }) else { throw PluginExecutionError.journalFull }
            next.remove(at: oldest)
        }
        let record = PluginExecutionRecord(id: UUID(), connectionID: connectionID, toolName: toolName, createdAt: now, state: .running)
        next.insert(record, at: 0)
        try save(next) // Failure must prevent the caller from dispatching.
        records = next
        return record.id
    }
    func finish(id: UUID, state: PluginExecutionState) throws {
        guard state != .running, let index = records.firstIndex(where: { $0.id == id && $0.state == .running }) else {
            throw PluginExecutionError.missingRecord
        }
        var next = records
        next[index].state = state
        try save(next)
        records = next
    }
    private func save(_ records: [PluginExecutionRecord]) throws {
        let data = try JSONEncoder().encode(Snapshot(records: records))
        guard data.count <= 262_144 else { throw PluginExecutionError.invalidJournal }
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }
}
