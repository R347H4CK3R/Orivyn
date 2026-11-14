import Foundation

/// Small protected task records only; no credentials or external synchronization.
@MainActor
final class LocalAgentStore {
    private struct Revision: Decodable { let revision: Int }
    private let directory: URL
    private let maximumRecords: Int
    init(directory: URL, maximumRecords: Int = 100) throws {
        self.maximumRecords = maximumRecords
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw LocalAgentError.storage }
        self.directory = directory
    }
    private func url(_ id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else { throw LocalAgentError.storage }
        return directory.appendingPathComponent(uuid.uuidString + ".json")
    }
    // Revision zero is the valid initial state in both current and legacy task
    // schemas. Reject malformed envelopes before writing, and classify malformed
    // on-disk records as unreadable without deleting or overwriting their bytes.
    private func verifyIdentity(_ raw: String, id: String) throws {
        guard raw.utf8.count <= 131_072, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["id"] as? String, let uuid = UUID(uuidString: value),
              uuid == UUID(uuidString: id),
              let revision = try? JSONDecoder().decode(Revision.self, from: data).revision,
              revision >= 0 else { throw LocalAgentError.storage }
    }
    func save(_ raw: String, id: String) throws {
        try verifyIdentity(raw, id: id)
        let file = try url(id)
        let exists = FileManager.default.fileExists(atPath: file.path)
        if exists {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { throw LocalAgentError.storage }
            let previous = try load(id: id)
            let oldRevision = try JSONDecoder().decode(Revision.self, from: Data(previous.utf8)).revision
            let newRevision = try JSONDecoder().decode(Revision.self, from: Data(raw.utf8)).revision
            guard newRevision > oldRevision || (newRevision == oldRevision && previous.utf8.elementsEqual(raw.utf8)) else { throw LocalAgentError.storage }
        } else {
            let archived = directory.appendingPathComponent("Archived", isDirectory: true).appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: archived.path) else { throw LocalAgentError.storage }
            guard try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).count < maximumRecords else { throw LocalAgentError.storage }
        }
        try Data(raw.utf8).write(to: file, options: [.atomic, .completeFileProtection])
    }
    func load(id: String) throws -> String {
        let file = try url(id)
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, let count = values.fileSize,
              count <= 131_072, let text = String(data: try Data(contentsOf: file), encoding: .utf8) else { throw LocalAgentError.storage }
        try verifyIdentity(text, id: id)
        return text
    }
    struct RecordBatch { let values: [String]; let unreadable: Int; let total: Int }
    func records(offset: Int = 0, limit: Int = 100) throws -> RecordBatch {
        guard offset >= 0, (1...100).contains(limit) else { throw LocalAgentError.storage }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        guard files.count <= maximumRecords else { throw LocalAgentError.storage }
        var values: [String] = [], unreadable = 0
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).dropFirst(offset).prefix(limit) {
            do { values.append(try load(id: file.deletingPathExtension().lastPathComponent)) }
            catch { unreadable += 1 } // Preserve damaged records; never overwrite/delete them.
        }
        return RecordBatch(values: values, unreadable: unreadable, total: files.count)
    }
    private func archiveStore() throws -> LocalAgentStore {
        try LocalAgentStore(directory: directory.appendingPathComponent("Archived", isDirectory: true), maximumRecords: 10_000)
    }
    func archivedRecords(page: Int = 0) throws -> RecordBatch {
        guard (0..<200).contains(page) else { throw LocalAgentError.storage }
        return try archiveStore().records(offset: page * 50, limit: 50)
    }
    /// Explicit user action only. Preserve bytes and never overwrite an existing record.
    func archive(id: String) throws {
        let value = try load(id: id)
        let target = try archiveStore()
        let destination = try target.url(id)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw LocalAgentError.storage }
        guard try FileManager.default.contentsOfDirectory(at: target.directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).count < target.maximumRecords else { throw LocalAgentError.storage }
        try target.verifyIdentity(value, id: id)
        try FileManager.default.moveItem(at: url(id), to: destination)
    }
    func restore(id: String) throws {
        let archived = try archiveStore()
        let value = try archived.load(id: id)
        let destination = try url(id)
        guard !FileManager.default.fileExists(atPath: destination.path),
              try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).count < maximumRecords else { throw LocalAgentError.storage }
        try verifyIdentity(value, id: id)
        try FileManager.default.moveItem(at: archived.url(id), to: destination)
    }

}
