import Foundation
import SQLite3

/// Owns the connection; all use is serialized by SQLiteConversationStore.
private final class DatabaseHandle: @unchecked Sendable {
    var raw: OpaquePointer?
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = DatabaseError.operation("Could not open local history.")
            if let raw { sqlite3_close(raw) }
            raw = nil
            throw error
        }
        sqlite3_busy_timeout(raw, 5_000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, title TEXT NOT NULL, updated REAL NOT NULL, archived INTEGER NOT NULL, search TEXT NOT NULL, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS memory (id TEXT PRIMARY KEY, content TEXT NOT NULL, created REAL NOT NULL, payload BLOB NOT NULL);")
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    deinit { if let raw { sqlite3_close(raw) } }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(raw, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.operation("The local database operation failed.") }
    }
}

enum DatabaseError: LocalizedError {
    case operation(String)
    var errorDescription: String? { switch self { case .operation(let text): text } }
}

actor SQLiteConversationStore {
    private let database: DatabaseHandle
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws { database = try DatabaseHandle(url: url) }

    func list(includeArchived: Bool = false, query: String = "") throws -> [Conversation] {
        let sql = "SELECT payload FROM conversations WHERE (? = 1 OR archived = 0) AND (? = '' OR instr(lower(search), lower(?)) > 0) ORDER BY updated DESC"
        return try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, includeArchived ? 1 : 0)
            bind(query, to: 2, in: statement); bind(query, to: 3, in: statement)
            var values: [Conversation] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw DatabaseError.operation("Could not search local history.") }
                values.append(try decodeConversation(blob(statement, at: 0)))
            }
            return values
        }
    }

    func load(id: UUID) throws -> Conversation? {
        try withStatement("SELECT payload FROM conversations WHERE id = ?") { statement in
            bind(id.uuidString, to: 1, in: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw DatabaseError.operation("Could not read this conversation.") }
            return try decodeConversation(blob(statement, at: 0))
        }
    }

    func save(_ conversation: Conversation) throws {
        try validate(conversation)
        let proposedImages = try validateImageIdentities(in: [conversation])
        try database.execute("BEGIN IMMEDIATE")
        do {
            // Streaming checkpoints normally change only message text. Compare this row first,
            // rather than decoding the entire history every time AppModel saves a checkpoint.
            // Removing all images cannot introduce a new cross-conversation identity conflict.
            if !proposedImages.isEmpty {
                let previous = try load(id: conversation.id)
                let previousImages = try validateImageIdentities(in: previous.map { [$0] } ?? [])
                if proposedImages != previousImages {
                    try validateMergedImageIdentities(replacing: [conversation])
                }
            }
            try writeConversation(conversation)
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    /// The caller validates the complete proposed state and owns its write transaction.
    private func writeConversation(_ conversation: Conversation) throws {
        let payload = try encoder.encode(conversation)
        try withStatement("INSERT INTO conversations (id,title,updated,archived,search,payload) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,updated=excluded.updated,archived=excluded.archived,search=excluded.search,payload=excluded.payload") { statement in
            bind(conversation.id.uuidString, to: 1, in: statement)
            bind(conversation.title, to: 2, in: statement)
            sqlite3_bind_double(statement, 3, conversation.updatedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement, 4, conversation.isArchived ? 1 : 0)
            bind(([conversation.title] + conversation.messages.map(\.content)).joined(separator: "\n"), to: 5, in: statement)
            bind(payload, to: 6, in: statement)
            try requireDone(statement)
        }
    }

    func delete(id: UUID) throws {
        try withStatement("DELETE FROM conversations WHERE id = ?") { statement in
            bind(id.uuidString, to: 1, in: statement); try requireDone(statement)
        }
    }

    /// A committed deletion must not be reported as rolled back if later disk
    /// compaction fails. The optional warning is separate from deletion success.
    @discardableResult
    func deleteAll() throws -> String? {
        try database.execute("BEGIN IMMEDIATE")
        do {
            try database.execute("DELETE FROM conversations; DELETE FROM memory; COMMIT;")
        } catch { try? database.execute("ROLLBACK"); throw error }
        do {
            try database.execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
            return nil
        } catch {
            return "Your conversations and memories were deleted, but database compaction could not finish. Storage may not be reclaimed yet; this is not a verified secure erase."
        }
    }

    func exportData() throws -> Data {
        let data = try encoder.encode(ConversationBackup(conversations: list(includeArchived: true), memories: memories()))
        guard data.count <= ConversationBackup.maximumBytes else { throw ConversationError.tooLarge }
        return data
    }

    /// Merges a complete validated snapshot transactionally. Attachments remain local references.
    @discardableResult
    func importData(_ data: Data, policy: BackupImportPolicy = .replaceMatching) throws -> BackupImportSummary {
        guard data.count <= ConversationBackup.maximumBytes else { throw ConversationError.tooLarge }
        let backup: ConversationBackup
        do { backup = try decoder.decode(ConversationBackup.self, from: data) }
        catch { throw ConversationError.invalidBackup }
        guard backup.schemaVersion == 1, backup.conversations.count <= 10_000, backup.memories.count <= 10_000,
              Set(backup.conversations.map(\.id)).count == backup.conversations.count,
              Set(backup.memories.map(\.id)).count == backup.memories.count else { throw ConversationError.invalidBackup }
        try backup.conversations.forEach(validate)
        try backup.memories.forEach(validateMemory)
        try database.execute("BEGIN IMMEDIATE")
        do {
            // Resolve preservation against the same locked snapshot used for writes.
            // No timestamp-based winner: clocks on another device are not trusted.
            var incomingConversations = backup.conversations
            var incomingMemories = backup.memories
            if policy == .preserveLocal {
                let conversationIDs = Set(try list(includeArchived: true).map(\.id))
                let memoryIDs = Set(try memories().map(\.id))
                incomingConversations.removeAll { conversationIDs.contains($0.id) }
                incomingMemories.removeAll { memoryIDs.contains($0.id) }
            }
            // Validate replacements together with untouched rows before changing either table.
            // Do not call save here: intermediate rows may conflict while a consistent batch
            // replaces every reference to an identity, and the transaction is already owned.
            try validateMergedImageIdentities(replacing: incomingConversations)
            for conversation in incomingConversations { try writeConversation(conversation) }
            for note in incomingMemories { try saveMemory(note) }
            try database.execute("COMMIT")
            return BackupImportSummary(writtenConversations: incomingConversations.count,
                                       writtenMemories: incomingMemories.count,
                                       skippedConversations: backup.conversations.count - incomingConversations.count,
                                       skippedMemories: backup.memories.count - incomingMemories.count)
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    func memories(query: String = "") throws -> [MemoryNote] {
        try withStatement("SELECT payload FROM memory WHERE ? = '' OR instr(lower(content),lower(?)) > 0 ORDER BY created DESC") { statement in
            bind(query, to: 1, in: statement); bind(query, to: 2, in: statement)
            var values: [MemoryNote] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw DatabaseError.operation("Could not read saved memory.") }
                values.append(try decoder.decode(MemoryNote.self, from: blob(statement, at: 0)))
            }
            return values
        }
    }

    func saveMemory(_ note: MemoryNote) throws {
        try validateMemory(note)
        let payload = try encoder.encode(note)
        try withStatement("INSERT INTO memory (id,content,created,payload) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET content=excluded.content,created=excluded.created,payload=excluded.payload") { statement in
            bind(note.id.uuidString, to: 1, in: statement); bind(note.content, to: 2, in: statement)
            sqlite3_bind_double(statement, 3, note.createdAt.timeIntervalSince1970)
            bind(payload, to: 4, in: statement); try requireDone(statement)
        }
    }
    func deleteMemory(id: UUID) throws {
        try withStatement("DELETE FROM memory WHERE id = ?") { statement in
            bind(id.uuidString, to: 1, in: statement); try requireDone(statement)
        }
    }
    private func decodeConversation(_ data: Data) throws -> Conversation {
        var value = try decoder.decode(Conversation.self, from: data)
        // An active stream is owned by AppModel. Persisted streams reopened from disk are interrupted.
        for index in value.messages.indices where value.messages[index].state == .streaming {
            value.messages[index].state = .interrupted
        }
        return value
    }
    private func validate(_ value: Conversation) throws {
        guard value.title.utf8.count <= 4_096, value.messages.count <= 50_000,
              Set(value.messages.map(\.id)).count == value.messages.count else { throw ConversationError.tooLarge }
        for message in value.messages {
            guard message.content.utf8.count <= 1_000_000, message.attachments.count <= 20 else { throw ConversationError.tooLarge }
            let imageIDs = message.attachments.filter(\.isImage).map(\.id)
            guard Set(imageIDs).count == imageIDs.count else { throw ConversationError.unsafeAttachment }
            for attachment in message.attachments {
                guard attachment.hasValidStorageBinding,
                      attachment.byteCount >= 0, attachment.byteCount <= 50_000_000,
                      attachment.name.utf8.count <= 1_024, (attachment.extractedText?.utf8.count ?? 0) <= 1_000_000
                else { throw ConversationError.unsafeAttachment }
            }
        }
        try validateImageIdentities(in: [value])
    }
    private func validateMergedImageIdentities(replacing replacements: [Conversation]) throws {
        guard !replacements.isEmpty else { return }
        let replacedIDs = Set(replacements.map(\.id))
        let retained = try list(includeArchived: true).filter { !replacedIDs.contains($0.id) }
        try validateImageIdentities(in: retained + replacements)
    }

    private struct ImageIdentity: Equatable {
        let relativePath: String
        let mediaType: String
        let byteCount: Int
    }

    @discardableResult
    private func validateImageIdentities(in conversations: [Conversation]) throws -> [UUID: ImageIdentity] {
        var identities: [UUID: ImageIdentity] = [:]
        for conversation in conversations {
            for message in conversation.messages {
                for image in message.attachments where image.isImage {
                    let identity = ImageIdentity(relativePath: image.relativePath, mediaType: image.mediaType, byteCount: image.byteCount)
                    if let existing = identities[image.id] {
                        guard existing == identity else { throw ConversationError.unsafeAttachment }
                    } else { identities[image.id] = identity }
                }
            }
        }
        return identities
    }
    private func validateMemory(_ note: MemoryNote) throws {
        guard !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.content.utf8.count <= 32_768 else { throw ConversationError.tooLarge }
    }
    private func withStatement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database.raw, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.operation("Could not prepare local storage.")
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }
    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), transient) }
    }
    private func bind(_ value: Data, to index: Int32, in statement: OpaquePointer) {
        _ = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
    }
    private func blob(_ statement: OpaquePointer, at index: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index)))
    }
    private func requireDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.operation("Could not save local changes.") }
    }
}
