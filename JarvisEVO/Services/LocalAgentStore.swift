import Foundation

/// Small protected task records only; no credentials or external synchronization.
@MainActor
final class LocalAgentStore {
    private struct Revision: Decodable { let revision: Int }
    private let directory: URL
    private let maximumRecords: Int
    private var preparedOrigins: [String: UUID] = [:]
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
    // Use the bounded strict parser before decoding: Foundation JSON readers can
    // disagree on duplicate keys, while the task reducer rejects such records.
    private func verifyIdentity(_ raw: String, id: String) throws {
        guard raw.utf8.count <= 131_072, let data = raw.data(using: .utf8),
              let object = try? MCPJSONValue.parse(data, maximumBytes: 131_072).objectValue,
              let value = object["id"]?.stringValue, let uuid = UUID(uuidString: value),
              uuid == UUID(uuidString: id),
              let revision = try? JSONDecoder().decode(Revision.self, from: data).revision,
              revision >= 0 else { throw LocalAgentError.storage }
    }
    /// Origin and reducer bytes share one atomic file. Absence of an envelope
    /// is legacy; a malformed or incomplete envelope is never treated as legacy.
    private func stored(id: String) throws -> (raw: String, origin: UUID?) {
        let file = try url(id)
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, let count = values.fileSize,
              count <= 263_000, let text = String(data: try Data(contentsOf: file), encoding: .utf8),
              let object = try MCPJSONValue.parse(Data(text.utf8), maximumBytes: 263_000).objectValue else { throw LocalAgentError.storage }
        if object["raw"] != nil || object["chatOrigin"] != nil {
            guard Set(object.keys) == Set(["raw", "chatOrigin"]), let raw = object["raw"]?.stringValue,
                  let originText = object["chatOrigin"]?.stringValue, let origin = UUID(uuidString: originText) else { throw LocalAgentError.storage }
            try verifyIdentity(raw, id: id)
            return (raw, origin)
        }
        try verifyIdentity(text, id: id)
        return (text, nil)
    }
    func origin(id: String) throws -> UUID? {
        let file = try url(id)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw LocalAgentError.storage }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        return try stored(id: id).origin
    }
    /// Preparation grants no execution. save atomically commits this association.
    func bindOrigin(id: String, conversationID: UUID) throws {
        let canonical = try url(id).lastPathComponent
        if let existing = try origin(id: id) {
            guard existing == conversationID else { throw LocalAgentError.storage }
        } else if FileManager.default.fileExists(atPath: try url(id).path) {
            throw LocalAgentError.storage // Never relabel a legacy task implicitly.
        }
        if let prepared = preparedOrigins[canonical] { guard prepared == conversationID else { throw LocalAgentError.storage } }
        guard preparedOrigins[canonical] != nil || preparedOrigins.count < maximumRecords else { throw LocalAgentError.storage }
        preparedOrigins[canonical] = conversationID
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
        let origin = try origin(id: id) ?? preparedOrigins[file.lastPathComponent]
        let bytes: Data
        if let origin {
            bytes = try MCPJSONValue.object(["chatOrigin": .string(origin.uuidString), "raw": .string(raw)]).encoded(maximumBytes: 263_000)
        } else { bytes = Data(raw.utf8) }
        try bytes.write(to: file, options: [.atomic, .completeFileProtection])
        preparedOrigins.removeValue(forKey: file.lastPathComponent)
    }
    func load(id: String) throws -> String { try stored(id: id).raw }
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
