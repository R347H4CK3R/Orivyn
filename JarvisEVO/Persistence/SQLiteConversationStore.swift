import Foundation
import SQLite3

/// Owns the connection; all use is serialized by SQLiteConversationStore.
private final class DatabaseHandle: @unchecked Sendable {
    var raw: OpaquePointer?
    init(url: URL) throws {
        var initialized = false
        defer {
            if !initialized, let raw {
                sqlite3_close(raw)
                self.raw = nil
            }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = DatabaseError.operation("Could not open local history.")
            if let raw { sqlite3_close(raw) }
            raw = nil
            throw error
        }
        sqlite3_busy_timeout(raw, 5_000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, title TEXT NOT NULL, updated REAL NOT NULL, archived INTEGER NOT NULL, search TEXT NOT NULL, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS memory (id TEXT PRIMARY KEY, content TEXT NOT NULL, created REAL NOT NULL, payload BLOB NOT NULL);")
        // A database-local receive epoch prevents old transfers resurrecting erased history.
        // Seed only a newly created schema; an existing but damaged epoch fails closed.
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(raw, "SELECT name FROM sqlite_master WHERE type='table' AND name='text_receive_epoch'", -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.operation("Could not inspect receive metadata.")
            }
            let status = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard status == SQLITE_ROW || status == SQLITE_DONE else { throw DatabaseError.operation("Could not inspect receive metadata.") }
            if status == SQLITE_DONE {
                try execute("CREATE TABLE text_receive_epoch (singleton INTEGER PRIMARY KEY CHECK(singleton=1), epoch TEXT NOT NULL); INSERT INTO text_receive_epoch VALUES (1, '\(UUID().uuidString)');")
                try execute("CREATE TABLE text_receive_receipts (transfer TEXT PRIMARY KEY, peer BLOB NOT NULL, generation TEXT NOT NULL, payload BLOB NOT NULL, summary BLOB NOT NULL);")
            }
            try execute("CREATE TABLE IF NOT EXISTS text_send_outbox (transfer TEXT PRIMARY KEY, sender BLOB NOT NULL, peer BLOB NOT NULL, generation TEXT NOT NULL, receiver_epoch TEXT NOT NULL, payload BLOB NOT NULL, delivered INTEGER NOT NULL DEFAULT 0 CHECK(delivered IN (0,1)));")
            // Both absent denotes the explicit legacy migration. Partial loss is
            // left damaged so ordinary history remains usable but sync fails closed.
            var revocationStatement: OpaquePointer?
            guard sqlite3_prepare_v2(raw,"SELECT name FROM sqlite_master WHERE type='table' AND name IN ('text_peer_revocation_state','text_peer_revocations')",-1,&revocationStatement,nil)==SQLITE_OK else { throw DatabaseError.operation("Could not inspect peer revocation metadata.") }
            var revocationTables=0
            while true {
                let step=sqlite3_step(revocationStatement)
                if step==SQLITE_DONE { break }
                guard step==SQLITE_ROW else { sqlite3_finalize(revocationStatement);throw DatabaseError.operation("Could not inspect peer revocation metadata.") }
                revocationTables += 1
            }
            sqlite3_finalize(revocationStatement)
            var versionStatement: OpaquePointer?
            guard sqlite3_prepare_v2(raw,"PRAGMA user_version",-1,&versionStatement,nil)==SQLITE_OK else { throw DatabaseError.operation("Could not inspect local schema version.") }
            guard sqlite3_step(versionStatement)==SQLITE_ROW else { sqlite3_finalize(versionStatement);throw DatabaseError.operation("Could not inspect local schema version.") }
            let schemaVersion=sqlite3_column_int64(versionStatement,0)
            sqlite3_finalize(versionStatement)
            if revocationTables==0 && schemaVersion==0 {
                try execute("CREATE TABLE text_peer_revocation_state (singleton INTEGER PRIMARY KEY CHECK(singleton=1), version INTEGER NOT NULL CHECK(version=1)); INSERT INTO text_peer_revocation_state VALUES (1,1); CREATE TABLE text_peer_revocations (peer BLOB NOT NULL CHECK(typeof(peer)='blob' AND length(peer)=32), generation TEXT NOT NULL CHECK(typeof(generation)='text' AND length(generation)=36), PRIMARY KEY(peer,generation)); PRAGMA user_version=1;")
            }
            try migrateTextLineageIfEligible()
            try migrateTextSenderIfEligible()
            try execute("CREATE TABLE IF NOT EXISTS archive_restore_receipts (job TEXT PRIMARY KEY, archive TEXT NOT NULL UNIQUE, epoch TEXT NOT NULL, payload BLOB NOT NULL, receipt BLOB NOT NULL);")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        initialized = true
    }
    /// Upgrade only a complete, known revocation schema. Lost metadata is not
    /// reconstructed; ordinary history can still open while sync remains paused.
    private func migrateTextLineageIfEligible() throws {
        func scalar(_ sql: String) -> Int64? {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(raw,sql,-1,&statement,nil)==SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_type(statement,0)==SQLITE_INTEGER else { return nil }
            let value=sqlite3_column_int64(statement,0)
            guard sqlite3_step(statement)==SQLITE_DONE else { return nil };return value
        }
        guard scalar("PRAGMA user_version")==1,
              scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('text_peer_revocation_state','text_peer_revocations')")==2,
              scalar("SELECT COUNT(*) FROM text_peer_revocation_state")==1,
              scalar("SELECT version FROM text_peer_revocation_state WHERE singleton=1 AND typeof(singleton)='integer' AND typeof(version)='integer'")==1,
              scalar("SELECT COUNT(*) FROM sqlite_master WHERE name='text_revision_lineage'")==0 else { return }
        try execute("CREATE TABLE text_revision_lineage (peer BLOB NOT NULL CHECK(typeof(peer)='blob' AND length(peer)=32), generation TEXT NOT NULL, source TEXT NOT NULL, local_id TEXT NOT NULL, remote_base BLOB NOT NULL, local_base BLOB NOT NULL, PRIMARY KEY(peer,generation,source), UNIQUE(peer,generation,local_id)); PRAGMA user_version=2;")
    }

    private func migrateTextSenderIfEligible() throws {
        func scalar(_ sql:String)->Int64? {
            var statement:OpaquePointer?
            guard sqlite3_prepare_v2(raw,sql,-1,&statement,nil)==SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_type(statement,0)==SQLITE_INTEGER else { return nil }
            let value=sqlite3_column_int64(statement,0)
            guard sqlite3_step(statement)==SQLITE_DONE else { return nil };return value
        }
        guard scalar("PRAGMA user_version")==2,
              scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('text_revision_lineage','text_peer_revocation_state','text_peer_revocations')")==3,
              scalar("SELECT COUNT(*) FROM text_peer_revocation_state")==1,
              scalar("SELECT version FROM text_peer_revocation_state WHERE singleton=1 AND typeof(singleton)='integer' AND typeof(version)='integer'")==1,
              scalar("SELECT COUNT(*) FROM sqlite_master WHERE name IN ('text_revision_outbox','text_revision_sent','text_revision_one_pending')")==0 else { return }
        try execute("CREATE TABLE text_revision_outbox (transfer TEXT PRIMARY KEY, sender BLOB NOT NULL, peer BLOB NOT NULL, generation TEXT NOT NULL, receiver_epoch TEXT NOT NULL, payload BLOB NOT NULL, delivered INTEGER NOT NULL DEFAULT 0 CHECK(delivered IN (0,1)), summary BLOB); CREATE UNIQUE INDEX text_revision_one_pending ON text_revision_outbox(peer,generation,receiver_epoch) WHERE delivered=0; CREATE TABLE text_revision_sent (sender BLOB NOT NULL, peer BLOB NOT NULL, generation TEXT NOT NULL, receiver_epoch TEXT NOT NULL, source TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(sender,peer,generation,receiver_epoch,source)); PRAGMA user_version=3;")
    }

    deinit { if let raw { sqlite3_close(raw) } }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(raw, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.operation("The local database operation failed.") }
    }
}

/// Local commit identity only: these fields do not authenticate a transport or grant consent.
struct ReviewedTextReceiveIdentity: Equatable, Sendable {
    let epoch: UUID
    let transfer: UUID
    let peerCertificateSHA256: Data
    let pairingGeneration: UUID
}

/// Durable local draft, not authentication, live transfer consent, or proof of
/// delivery. Only a future authenticated receipt handler may record delivery.
struct TextSendIdentity: Equatable, Sendable {
    let receiverEpoch: UUID
    let transfer: UUID
    let senderCertificateSHA256: Data
    let receiverCertificateSHA256: Data
    let pairingGeneration: UUID
    /// Receiver-side pin identifies the sender, not the destination certificate.
    var receiveIdentity: ReviewedTextReceiveIdentity {
        ReviewedTextReceiveIdentity(epoch: receiverEpoch, transfer: transfer,
            peerCertificateSHA256: senderCertificateSHA256, pairingGeneration: pairingGeneration)
    }
}

struct StagedTextSend: Sendable {
    let identity: TextSendIdentity
    let payload: Data
    let delivered: Bool
}

enum DatabaseError: LocalizedError {
    case operation(String)
    var errorDescription: String? { switch self { case .operation(let text): text } }
}

struct ArchiveRestoreReceipt: Codable, Equatable, Sendable {
    let jobID: UUID
    let archiveSHA256: String
    let epoch: UUID
    let writtenConversations: Int
    let preservedConversations: Int
}

actor SQLiteConversationStore {
    private let database: DatabaseHandle
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws { database = try DatabaseHandle(url: url) }

    /// Commits only a fully prepared, explicitly reviewed text restore. The caller
    /// owns archive/plan SHA verification and Files permissions. Exact canonical
    /// bytes bind replay; attachments require a separate ownership-proof API.
    /// A returned receipt means COMMIT succeeded even if the caller's later reload fails.
    func applyArchiveRestore(jobID: UUID, archiveSHA256: String, expectedEpoch: UUID, conversations: [Conversation]) throws -> ArchiveRestoreReceipt {
        try Task.checkCancellation()
        guard archiveSHA256.count == 64,
              archiveSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              conversations.count <= ConversationBackup.maximumRecordsPerCollection,
              Set(conversations.map(\.id)).count == conversations.count else { throw ConversationError.invalidBackup }
        for conversation in conversations {
            try validate(conversation)
            guard conversation.messages.allSatisfy({ $0.attachments.isEmpty && $0.state != .streaming }) else { throw ConversationError.unsafeAttachment }
        }
        let canonical = JSONEncoder(); canonical.outputFormatting = [.sortedKeys]
        let payload = try canonical.encode(conversations)
        guard payload.count <= ConversationBackup.maximumBytes else { throw ConversationError.tooLarge }
        try Task.checkCancellation()
        try database.execute("BEGIN IMMEDIATE")
        do {
            guard try textReceiveEpoch() == expectedEpoch else { throw DatabaseError.operation("This archive restore predates local history erasure. Prepare and review it again.") }
            let prior: ArchiveRestoreReceipt? = try withStatement("SELECT job,archive,epoch,payload,receipt FROM archive_restore_receipts WHERE job=? OR archive=?") { statement in
                bind(jobID.uuidString, to: 1, in: statement); bind(archiveSHA256, to: 2, in: statement)
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return nil }
                guard status == SQLITE_ROW else { throw DatabaseError.operation("Could not inspect archive restore receipt.") }
                let receipt = try decoder.decode(ArchiveRestoreReceipt.self, from: blob(statement, at: 4))
                guard let jobColumn = sqlite3_column_text(statement, 0),
                      let archiveColumn = sqlite3_column_text(statement, 1),
                      let epochColumn = sqlite3_column_text(statement, 2),
                      String(cString: jobColumn) == receipt.jobID.uuidString,
                      String(cString: archiveColumn) == receipt.archiveSHA256,
                      String(cString: epochColumn) == receipt.epoch.uuidString,
                      receipt.archiveSHA256 == archiveSHA256, receipt.epoch == expectedEpoch,
                      receipt.writtenConversations >= 0, receipt.preservedConversations >= 0,
                      receipt.writtenConversations <= conversations.count,
                      receipt.preservedConversations == conversations.count - receipt.writtenConversations,
                      blob(statement, at: 3) == payload else { throw DatabaseError.operation("Archive restore identity is already bound to a different reviewed plan.") }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.operation("Archive restore identities conflict.") }
                return receipt
            }
            if let prior { try Task.checkCancellation(); try database.execute("COMMIT"); return prior }
            let retained = try withStatement("SELECT COALESCE(SUM(length(payload)),0),COUNT(*) FROM archive_restore_receipts") { statement in
                guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int64(statement, 1) < 1000 else { throw DatabaseError.operation("Archive receipt capacity reached.") }
                return sqlite3_column_int64(statement, 0)
            }
            guard retained >= 0, retained <= Int64(ConversationBackup.maximumBytes - payload.count) else { throw DatabaseError.operation("Archive receipt capacity reached.") }
            let localIDs = Set(try list(includeArchived: true).map(\.id))
            let additions = conversations.filter { !localIDs.contains($0.id) }
            guard localIDs.count + additions.count <= ConversationBackup.maximumRecordsPerCollection else { throw ConversationError.backupRecordLimit }
            for conversation in additions { try Task.checkCancellation(); try writeConversation(conversation) }
            let receipt = ArchiveRestoreReceipt(jobID: jobID, archiveSHA256: archiveSHA256, epoch: expectedEpoch,
                writtenConversations: additions.count, preservedConversations: conversations.count - additions.count)
            try withStatement("INSERT INTO archive_restore_receipts(job,archive,epoch,payload,receipt) VALUES(?,?,?,?,?)") { statement in
                bind(jobID.uuidString, to: 1, in: statement); bind(archiveSHA256, to: 2, in: statement)
                bind(expectedEpoch.uuidString, to: 3, in: statement); bind(payload, to: 4, in: statement)
                bind(try canonical.encode(receipt), to: 5, in: statement); try requireDone(statement)
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
            return receipt
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    /// Historical commit evidence, not a claim that the UI has reloaded the rows.
    func archiveRestoreReceipt(jobID: UUID) throws -> ArchiveRestoreReceipt? {
        try withStatement("SELECT job,archive,epoch,receipt FROM archive_restore_receipts WHERE job=?") { statement in
            bind(jobID.uuidString, to: 1, in: statement)
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW else { throw DatabaseError.operation("Could not read archive restore receipt.") }
            let receipt = try decoder.decode(ArchiveRestoreReceipt.self, from: blob(statement, at: 3))
            guard let jobColumn = sqlite3_column_text(statement, 0),
                  let archiveColumn = sqlite3_column_text(statement, 1),
                  let epochColumn = sqlite3_column_text(statement, 2),
                  String(cString: jobColumn) == receipt.jobID.uuidString,
                  String(cString: archiveColumn) == receipt.archiveSHA256,
                  String(cString: epochColumn) == receipt.epoch.uuidString,
                  receipt.jobID == jobID, receipt.writtenConversations >= 0,
                  receipt.preservedConversations >= 0,
                  receipt.writtenConversations <= ConversationBackup.maximumRecordsPerCollection,
                  receipt.preservedConversations <= ConversationBackup.maximumRecordsPerCollection - receipt.writtenConversations
            else { throw DatabaseError.operation("Archive receipt identity is invalid.") }
            return receipt
        }
    }

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
        try database.execute("BEGIN IMMEDIATE")
        do {
            try withStatement("DELETE FROM conversations WHERE id = ?") { statement in
                bind(id.uuidString, to: 1, in: statement); try requireDone(statement)
            }
            // Receipts contain exact text bytes. Clear them on individual erasure too,
            // and invalidate every prior receive scope rather than resurrect deleted text.
            try invalidateTextReceivesForErasure()
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    /// A committed deletion must not be reported as rolled back if later disk
    /// compaction fails. The optional warning is separate from deletion success.
    @discardableResult
    func deleteAll() throws -> String? {
        try database.execute("BEGIN IMMEDIATE")
        do {
            try database.execute("DELETE FROM conversations; DELETE FROM memory;")
            try invalidateTextReceivesForErasure()
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
        do {
            try database.execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
            return nil
        } catch {
            return "Your conversations and memories were deleted, but database compaction could not finish. Storage may not be reclaimed yet; this is not a verified secure erase."
        }
    }

    private func tableExists(_ name: String) throws -> Bool {
        try withStatement("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?") { statement in
            bind(name, to: 1, in: statement)
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW || result == SQLITE_DONE else {
                throw DatabaseError.operation("Could not inspect local text transfer metadata.")
            }
            return result == SQLITE_ROW
        }
    }

    /// Runs inside the caller's erasure transaction. Missing receive metadata must
    /// not prevent user erasure. Do not recreate it: receives still fail closed.
    private func invalidateTextReceivesForErasure() throws {
        if try tableExists("archive_restore_receipts") {
            try database.execute("DELETE FROM archive_restore_receipts")
        }
        if try tableExists("text_receive_receipts") {
            // Real failures still roll back: otherwise private receipt text could remain.
            try database.execute("DELETE FROM text_receive_receipts")
        }
        if try tableExists("text_send_outbox") {
            // Pending and delivered rows both retain exact reviewed private bytes.
            try database.execute("DELETE FROM text_send_outbox")
        }
        for table in ["text_revision_lineage","text_revision_outbox","text_revision_sent"] where try tableExists(table) { try database.execute("DELETE FROM \(table)") }
        if try tableExists("text_receive_epoch") {
            try database.execute("UPDATE text_receive_epoch SET epoch='\(UUID().uuidString)' WHERE singleton=1")
        }
    }

    func exportData() throws -> Data {
        // A backup must represent one committed database snapshot. Another
        // connection may import both tables between these reads; actor isolation
        // only serializes this connection, not every store using the same file.
        try database.execute("BEGIN")
        do {
            let conversations = try list(includeArchived: true)
            let notes = try memories()
            guard conversations.count <= ConversationBackup.maximumRecordsPerCollection,
                  notes.count <= ConversationBackup.maximumRecordsPerCollection else {
                throw ConversationError.backupRecordLimit
            }
            let data = try encoder.encode(ConversationBackup(conversations: conversations, memories: notes))
            guard data.count <= ConversationBackup.maximumBytes else { throw ConversationError.tooLarge }
            try database.execute("COMMIT")
            return data
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    /// Selects only requested records from one committed read transaction. The
    /// immutable returned bytes are both reviewed and exported, never re-queried.
    func exportTextSnapshot(ids: Set<UUID>) throws -> ReviewedTextSnapshot {
        try Task.checkCancellation()
        guard (1...ReviewedTextSnapshot.maximumConversations).contains(ids.count) else { throw TextSnapshotError.selection }
        try database.execute("BEGIN")
        do {
            var values: [Conversation] = []
            var retainedBytes = 0
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                try Task.checkCancellation()
                let value = try withStatement("SELECT payload FROM conversations WHERE id = ?") { statement in
                    bind(id.uuidString, to: 1, in: statement)
                    let status = sqlite3_step(statement)
                    guard status != SQLITE_DONE else { throw TextSnapshotError.changed }
                    guard status == SQLITE_ROW else { throw DatabaseError.operation("Could not read the selected conversation.") }
                    let count = Int(sqlite3_column_bytes(statement, 0))
                    guard count > 0, count <= ReviewedTextSnapshot.maximumBytes - retainedBytes else { throw TextSnapshotError.limit }
                    retainedBytes += count
                    let conversation = try decodeConversation(blob(statement, at: 0))
                    try validate(conversation)
                    guard conversation.id == id else { throw TextSnapshotError.changed }
                    return conversation
                }
                values.append(value)
            }
            let snapshot = try ReviewedTextSnapshot(conversations: values)
            try Task.checkCancellation()
            try database.execute("COMMIT")
            return snapshot
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    /// A durable rejection list only. Absence never authenticates a peer or grants
    /// transport/receive consent. Native session invalidation is still required.
    func isTextPeerRevoked(peerCertificateSHA256: Data, pairingGeneration: UUID) throws -> Bool {
        guard peerCertificateSHA256.count == 32 else { throw DatabaseError.operation("Invalid peer revocation scope.") }
        try validateTextRevocationMetadata()
        return try withStatement("SELECT 1 FROM text_peer_revocations WHERE peer=? AND generation=?") { statement in
            bind(peerCertificateSHA256,to:1,in:statement);bind(pairingGeneration.uuidString,to:2,in:statement)
            let status=sqlite3_step(statement)
            guard status==SQLITE_ROW || status==SQLITE_DONE else { throw DatabaseError.operation("Peer revocation metadata needs recovery.") }
            return status==SQLITE_ROW
        }
    }

    /// Revocation and scope-specific private transfer-metadata cleanup are one
    /// transaction. Already committed conversations are preserved, not retracted.
    /// Tombstones survive history erasure and have no silent expiry or eviction.
    func revokeTextPeer(peerCertificateSHA256: Data, pairingGeneration: UUID) throws {
        try Task.checkCancellation()
        guard peerCertificateSHA256.count == 32 else { throw DatabaseError.operation("Invalid peer revocation scope.") }
        try database.execute("BEGIN IMMEDIATE")
        do {
            if try !isTextPeerRevoked(peerCertificateSHA256:peerCertificateSHA256,pairingGeneration:pairingGeneration) {
                try withStatement("SELECT COUNT(*) FROM text_peer_revocations") { statement in
                    guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_int64(statement,0)<10_000 else {
                        throw DatabaseError.operation("Peer revocation storage is full; revocation was not committed.")
                    }
                }
                try withStatement("INSERT INTO text_peer_revocations (peer,generation) VALUES (?,?)") { statement in
                    bind(peerCertificateSHA256,to:1,in:statement);bind(pairingGeneration.uuidString,to:2,in:statement);try requireDone(statement)
                }
            }
            // Missing unrelated transfer tables cannot prevent revocation. If an
            // existing table cannot be cleared, report failure and roll back both.
            for table in ["text_send_outbox","text_receive_receipts","text_revision_lineage","text_revision_outbox","text_revision_sent"] where try tableExists(table) {
                try withStatement("DELETE FROM \(table) WHERE peer=? AND generation=?") { statement in
                    bind(peerCertificateSHA256,to:1,in:statement);bind(pairingGeneration.uuidString,to:2,in:statement);try requireDone(statement)
                }
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK");throw error }
    }

    private func validateTextRevocationMetadata() throws {
        // Deliberately no creation/repair here: lost state must never revive a peer.
        // The SQLite header sentinel distinguishes a real legacy DB from loss of
        // both metadata tables. It is not authenticated rollback/tamper detection.
        try withStatement("PRAGMA user_version") { statement in
            guard sqlite3_step(statement)==SQLITE_ROW,[1,2,3].contains(sqlite3_column_int64(statement,0)) else { throw DatabaseError.operation("Peer revocation schema needs recovery; text sync is paused.") }
        }
        guard try tableExists("text_peer_revocations") else { throw DatabaseError.operation("Peer revocation metadata needs recovery; text sync is paused.") }
        try withStatement("SELECT singleton,version FROM text_peer_revocation_state") { statement in
            guard sqlite3_step(statement)==SQLITE_ROW,
                  sqlite3_column_type(statement,0)==SQLITE_INTEGER,sqlite3_column_int64(statement,0)==1,
                  sqlite3_column_type(statement,1)==SQLITE_INTEGER,sqlite3_column_int64(statement,1)==1,
                  sqlite3_step(statement)==SQLITE_DONE else { throw DatabaseError.operation("Peer revocation metadata needs recovery; text sync is paused.") }
        }
    }

    private func requireTextPeerNotRevoked(_ peer: Data, generation: UUID) throws {
        guard try !isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation) else {
            throw DatabaseError.operation("This peer pairing generation is revoked; no text transfer was accepted.")
        }
    }


    /// Dormant sender boundary. This stages exact reviewed bytes, not permission
    /// to transmit. One pending envelope per destination serializes its revisions.
    func stageTextRevisionSend(_ snapshot:ReviewedTextSnapshot, senderCertificateSHA256:Data,
                               peerCertificateSHA256:Data, pairingGeneration:UUID, receiverEpoch:UUID) throws -> StagedTextSend {
        try Task.checkCancellation()
        guard senderCertificateSHA256.count==32,peerCertificateSHA256.count==32,
              senderCertificateSHA256 != peerCertificateSHA256 else { throw DatabaseError.operation("Invalid revision destination.") }
        try database.execute("BEGIN IMMEDIATE")
        do {
            try requireTextSenderMetadata()
            try requireTextPeerNotRevoked(peerCertificateSHA256,generation:pairingGeneration)
            let identity=TextSendIdentity(receiverEpoch:receiverEpoch,transfer:UUID(),senderCertificateSHA256:senderCertificateSHA256,receiverCertificateSHA256:peerCertificateSHA256,pairingGeneration:pairingGeneration)
            var records:[TextRevisionEnvelope.Record]=[]
            for selected in snapshot.conversations {
                try Task.checkCancellation()
                guard try rawRevisionConversation(id:selected.id)==selected else { throw TextSnapshotError.changed }
                records.append(.init(base:try sentRevisionBase(source:selected.id,identity:identity),incoming:selected))
            }
            let payload=try TextRevisionEnvelope(records:records).data
            try withStatement("SELECT COUNT(*),COALESCE(SUM(length(payload)+COALESCE(length(summary),0)),0) FROM text_revision_outbox") { statement in
                guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_int64(statement,0)<10_000,
                      sqlite3_column_int64(statement,1)<=50_000_000-Int64(payload.count) else {
                    throw DatabaseError.operation("Revision outbox capacity reached; no transfer staged.")
                }
            }
            // The partial unique index rejects concurrent envelopes even from
            // a second store connection. Never silently replace a pending transfer.
            try withStatement("INSERT INTO text_revision_outbox(transfer,sender,peer,generation,receiver_epoch,payload) VALUES(?,?,?,?,?,?)") { statement in
                bind(identity.transfer.uuidString,to:1,in:statement);bind(senderCertificateSHA256,to:2,in:statement)
                bind(peerCertificateSHA256,to:3,in:statement);bind(pairingGeneration.uuidString,to:4,in:statement)
                bind(receiverEpoch.uuidString,to:5,in:statement);bind(payload,to:6,in:statement);try requireDone(statement)
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
            return StagedTextSend(identity:identity,payload:payload,delivered:false)
        } catch { try? database.execute("ROLLBACK");throw error }
    }

    func pendingTextRevisionSendIDs() throws -> [UUID] {
        try requireTextSenderMetadata()
        return try withStatement("SELECT transfer FROM text_revision_outbox WHERE delivered=0 ORDER BY transfer LIMIT 10001") { statement in
            var result:[UUID]=[]
            while true {
                let step=sqlite3_step(statement)
                if step==SQLITE_DONE { return result }
                guard step==SQLITE_ROW,result.count<10_000,sqlite3_column_type(statement,0)==SQLITE_TEXT,
                      sqlite3_column_bytes(statement,0)==36,let raw=sqlite3_column_text(statement,0),
                      let id=UUID(uuidString:String(cString:raw)) else { throw DatabaseError.operation("Revision outbox needs recovery.") }
                result.append(id)
            }
        }
    }

    /// Snapshot for a future authenticated coordinator; not a live send lease.
    /// A coordinator must invalidate in-flight work on lock, erase or revocation.
    func textRevisionSend(id:UUID) throws -> StagedTextSend? {
        try requireTextSenderMetadata()
        return try withStatement("SELECT sender,peer,generation,receiver_epoch,payload,delivered,summary FROM text_revision_outbox WHERE transfer=?") { statement in
            bind(id.uuidString,to:1,in:statement)
            let step=sqlite3_step(statement)
            if step==SQLITE_DONE { return nil }
            guard step==SQLITE_ROW,
                  sqlite3_column_type(statement,0)==SQLITE_BLOB,sqlite3_column_bytes(statement,0)==32,
                  sqlite3_column_type(statement,1)==SQLITE_BLOB,sqlite3_column_bytes(statement,1)==32,
                  sqlite3_column_type(statement,2)==SQLITE_TEXT,sqlite3_column_bytes(statement,2)==36,
                  sqlite3_column_type(statement,3)==SQLITE_TEXT,sqlite3_column_bytes(statement,3)==36,
                  let generationText=sqlite3_column_text(statement,2),let generation=UUID(uuidString:String(cString:generationText)),
                  let epochText=sqlite3_column_text(statement,3),let epoch=UUID(uuidString:String(cString:epochText)),
                  sqlite3_column_type(statement,4)==SQLITE_BLOB,
                  (1...TextRevisionEnvelope.maximumBytes).contains(Int(sqlite3_column_bytes(statement,4))),
                  sqlite3_column_type(statement,5)==SQLITE_INTEGER,[0,1].contains(sqlite3_column_int(statement,5)) else {
                throw DatabaseError.operation("Revision outbox needs recovery.")
            }
            let sender=blob(statement,at:0),peer=blob(statement,at:1)
            guard sender != peer else { throw DatabaseError.operation("Invalid revision destination.") }
            try requireTextPeerNotRevoked(peer,generation:generation)
            let payload=blob(statement,at:4),envelope=try TextRevisionEnvelope.decodeCanonical(payload)
            let delivered=sqlite3_column_int(statement,5)==1
            if delivered {
                guard sqlite3_column_type(statement,6)==SQLITE_BLOB,(1...50_000).contains(Int(sqlite3_column_bytes(statement,6))) else {
                    throw DatabaseError.operation("Revision delivery metadata is incomplete.")
                }
                let bytes=blob(statement,at:6),summary=try decoder.decode(TextRevisionReceiveSummary.self,from:bytes)
                guard try revisionSummaryBytes(summary,envelope:envelope)==bytes else { throw DatabaseError.operation("Revision receipt is not canonical.") }
            } else {
                guard sqlite3_column_type(statement,6)==SQLITE_NULL else { throw DatabaseError.operation("Pending revision has inconsistent delivery metadata.") }
            }
            return StagedTextSend(identity:.init(receiverEpoch:epoch,transfer:id,senderCertificateSHA256:sender,receiverCertificateSHA256:peer,pairingGeneration:generation),payload:payload,delivered:delivered)
        }
    }

    /// Only an authenticated receipt handler may call this after binding identity,
    /// payload and summary. Socket-send completion is never evidence of delivery.
    /// A replay must match the original receipt exactly and never rewinds ancestry.
    func recordTextRevisionDeliveryReceipt(identity:TextSendIdentity,payload:Data,summary:TextRevisionReceiveSummary) throws {
        try Task.checkCancellation()
        guard !payload.isEmpty,payload.count<=TextRevisionEnvelope.maximumBytes,summary.records.count<=100 else { throw TextSnapshotError.limit }
        try database.execute("BEGIN IMMEDIATE")
        do {
            guard let staged=try textRevisionSend(id:identity.transfer),staged.identity==identity,staged.payload==payload else {
                throw DatabaseError.operation("Revision receipt does not match the staged transfer.")
            }
            let envelope=try TextRevisionEnvelope.decodeCanonical(payload)
            let receipt=try revisionSummaryBytes(summary,envelope:envelope)
            if staged.delivered {
                try withStatement("SELECT summary FROM text_revision_outbox WHERE transfer=?") { statement in
                    bind(identity.transfer.uuidString,to:1,in:statement)
                    guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_bytes(statement,0)==receipt.count,
                          blob(statement,at:0)==receipt else { throw DatabaseError.operation("Revision replay changed its receipt.") }
                }
                try database.execute("COMMIT")
                return
            }
            for record in envelope.records {
                try Task.checkCancellation()
                guard try sentRevisionBase(source:record.incoming.id,identity:identity)==record.base else {
                    throw DatabaseError.operation("Outgoing revision ancestry changed; receipt was not applied.")
                }
                let current=try TextRevisionEnvelope.canonicalConversation(record.incoming)
                try withStatement("INSERT INTO text_revision_sent(sender,peer,generation,receiver_epoch,source,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(sender,peer,generation,receiver_epoch,source) DO UPDATE SET payload=excluded.payload") { statement in
                    bindRevisionScope(identity,in:statement);bind(record.incoming.id.uuidString,to:5,in:statement)
                    bind(current,to:6,in:statement);try requireDone(statement)
                }
            }
            try withStatement("SELECT COUNT(*),COALESCE(SUM(length(payload)),0) FROM text_revision_sent") { statement in
                guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_int64(statement,0)<=10_000,
                      sqlite3_column_int64(statement,1)<=50_000_000 else { throw DatabaseError.operation("Sent revision capacity reached; receipt rolled back.") }
            }
            try withStatement("SELECT COALESCE(SUM(length(payload)+COALESCE(length(summary),0)),0) FROM text_revision_outbox") { statement in
                guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_int64(statement,0)<=50_000_000-Int64(receipt.count) else {
                    throw DatabaseError.operation("Revision receipt capacity reached; receipt rolled back.")
                }
            }
            try withStatement("UPDATE text_revision_outbox SET delivered=1,summary=? WHERE transfer=?") { statement in
                bind(receipt,to:1,in:statement);bind(identity.transfer.uuidString,to:2,in:statement);try requireDone(statement)
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK");throw error }
    }

    /// Removes only the retry record. Acknowledged ancestry remains until explicit
    /// history erasure or pairing revocation; deleting a draft is not a remote undo.
    func discardTextRevisionSend(id:UUID) throws {
        try withStatement("DELETE FROM text_revision_outbox WHERE transfer=?") { statement in
            bind(id.uuidString,to:1,in:statement);try requireDone(statement)
        }
    }

    private func requireTextSenderMetadata() throws {
        try validateTextRevocationMetadata()
        try withStatement("PRAGMA user_version") { statement in
            guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_int64(statement,0)==3 else { throw DatabaseError.operation("Revision sender metadata needs recovery.") }
        }
        for name in ["text_revision_sent","text_revision_outbox"] {
            guard try tableExists(name) else { throw DatabaseError.operation("Revision sender metadata is unavailable.") }
        }
        try withStatement("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='text_revision_one_pending' AND tbl_name='text_revision_outbox'") { statement in
            guard sqlite3_step(statement)==SQLITE_ROW,sqlite3_column_int64(statement,0)==1 else { throw DatabaseError.operation("Revision sender serialization needs recovery.") }
        }
    }

    private func bindRevisionScope(_ identity:TextSendIdentity,in statement:OpaquePointer) {
        bind(identity.senderCertificateSHA256,to:1,in:statement);bind(identity.receiverCertificateSHA256,to:2,in:statement)
        bind(identity.pairingGeneration.uuidString,to:3,in:statement);bind(identity.receiverEpoch.uuidString,to:4,in:statement)
    }

    private func sentRevisionBase(source:UUID,identity:TextSendIdentity) throws -> Conversation? {
        try withStatement("SELECT payload FROM text_revision_sent WHERE sender=? AND peer=? AND generation=? AND receiver_epoch=? AND source=?") { statement in
            bindRevisionScope(identity,in:statement);bind(source.uuidString,to:5,in:statement)
            let step=sqlite3_step(statement)
            if step==SQLITE_DONE { return nil }
            guard step==SQLITE_ROW,sqlite3_column_type(statement,0)==SQLITE_BLOB,
                  (1...TextRevisionEnvelope.maximumBytes).contains(Int(sqlite3_column_bytes(statement,0))) else {
                throw DatabaseError.operation("Acknowledged revision ancestry needs recovery.")
            }
            let bytes=blob(statement,at:0),value=try decoder.decode(Conversation.self,from:bytes)
            _=try ReviewedTextSnapshot(conversations:[value])
            guard value.id==source,try TextRevisionEnvelope.canonicalConversation(value)==bytes else {
                throw DatabaseError.operation("Acknowledged revision ancestry is inconsistent.")
            }
            return value
        }
    }

    private func revisionSummaryBytes(_ summary:TextRevisionReceiveSummary,envelope:TextRevisionEnvelope) throws -> Data {
        guard summary.records.count==envelope.records.count,
              summary.records.map(\.sourceID)==envelope.records.map({$0.incoming.id}),
              Set(summary.records.map(\.localID)).count==summary.records.count else { throw DatabaseError.operation("Revision receipt has different source records.") }
        for (result,record) in zip(summary.records,envelope.records) {
            switch result.disposition {
            case .inserted:
                guard record.base==nil,result.localID==record.incoming.id,result.preservedLocalID==nil else { throw DatabaseError.operation("Invalid inserted revision receipt.") }
            case .advanced:
                guard let base=record.base,base != record.incoming,result.preservedLocalID==nil else { throw DatabaseError.operation("Invalid advanced revision receipt.") }
            case .unchanged:
                guard record.base==record.incoming,result.preservedLocalID==nil else { throw DatabaseError.operation("Invalid unchanged revision receipt.") }
            case .conflict:
                guard let preserved=result.preservedLocalID,preserved != result.localID else { throw DatabaseError.operation("Invalid conflict revision receipt.") }
            }
        }
        let canonical=JSONEncoder();canonical.outputFormatting = .sortedKeys
        let bytes=try canonical.encode(summary)
        guard bytes.count<=50_000 else { throw TextSnapshotError.limit }
        return bytes
    }

    /// Locally stages precisely the reviewed snapshot and destination labels.
    /// This performs no network operation and grants no authority to send bytes.
    /// Reject a changed/deleted selection instead of rebuilding reviewed content.
    func stageTextSend(_ snapshot: ReviewedTextSnapshot, senderCertificateSHA256: Data, peerCertificateSHA256: Data,
                       pairingGeneration: UUID, receiverEpoch: UUID) throws -> StagedTextSend {
        try Task.checkCancellation()
        guard senderCertificateSHA256.count == 32, peerCertificateSHA256.count == 32,
              senderCertificateSHA256 != peerCertificateSHA256 else { throw DatabaseError.operation("Invalid text send destination.") }
        try database.execute("BEGIN IMMEDIATE")
        do {
            try requireTextPeerNotRevoked(peerCertificateSHA256,generation:pairingGeneration)
            for selected in snapshot.conversations {
                try Task.checkCancellation()
                try withStatement("SELECT payload FROM conversations WHERE id=?") { statement in
                    bind(selected.id.uuidString, to: 1, in: statement)
                    guard sqlite3_step(statement) == SQLITE_ROW,
                          (1...ReviewedTextSnapshot.maximumBytes).contains(Int(sqlite3_column_bytes(statement, 0))) else {
                        throw TextSnapshotError.changed
                    }
                    // Preserve persisted stream state here: do not turn an active
                    // checkpoint into a resumable approved snapshot during reload.
                    let current = try decoder.decode(Conversation.self, from: blob(statement, at: 0))
                    guard current == selected else { throw TextSnapshotError.changed }
                }
            }
            try withStatement("SELECT COUNT(*), COALESCE(SUM(length(payload)),0) FROM text_send_outbox") { statement in
                guard sqlite3_step(statement) == SQLITE_ROW,
                      sqlite3_column_int64(statement, 0) < 10_000,
                      sqlite3_column_int64(statement, 1) <= 50_000_000 - Int64(snapshot.data.count) else {
                    throw DatabaseError.operation("Text send storage is full; no draft was staged.")
                }
            }
            let identity = TextSendIdentity(receiverEpoch: receiverEpoch, transfer: UUID(), senderCertificateSHA256: senderCertificateSHA256,
                receiverCertificateSHA256: peerCertificateSHA256, pairingGeneration: pairingGeneration)
            try withStatement("INSERT INTO text_send_outbox (transfer,sender,peer,generation,receiver_epoch,payload) VALUES (?,?,?,?,?,?)") { statement in
                bind(identity.transfer.uuidString, to: 1, in: statement)
                bind(identity.senderCertificateSHA256, to: 2, in: statement)
                bind(identity.receiverCertificateSHA256, to: 3, in: statement)
                bind(identity.pairingGeneration.uuidString, to: 4, in: statement)
                bind(identity.receiverEpoch.uuidString, to: 5, in: statement)
                bind(snapshot.data, to: 6, in: statement)
                try requireDone(statement)
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
            return StagedTextSend(identity: identity, payload: snapshot.data, delivered: false)
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    /// Metadata only. Restart discovers pending drafts; it does not resume sending.
    func pendingTextSendIDs() throws -> [UUID] {
        try validateTextRevocationMetadata()
        return try withStatement("SELECT transfer FROM text_send_outbox WHERE delivered=0 ORDER BY transfer LIMIT 10001") { statement in
            var result: [UUID] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return result }
                guard status == SQLITE_ROW, result.count < 10_000,
                      let text = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: text)) else {
                    throw DatabaseError.operation("Could not read staged text sends.")
                }
                result.append(id)
            }
        }
    }

    func textSend(id: UUID) throws -> StagedTextSend? {
        try validateTextRevocationMetadata()
        return try withStatement("SELECT peer,generation,receiver_epoch,payload,delivered,sender FROM text_send_outbox WHERE transfer=?") { statement in
            bind(id.uuidString, to: 1, in: statement)
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW,
                  sqlite3_column_bytes(statement, 0) == 32, sqlite3_column_bytes(statement, 5) == 32,
                  blob(statement, at: 0) != blob(statement, at: 5),
                  let generationText = sqlite3_column_text(statement, 1), let generation = UUID(uuidString: String(cString: generationText)),
                  let epochText = sqlite3_column_text(statement, 2), let epoch = UUID(uuidString: String(cString: epochText)),
                  (1...ReviewedTextSnapshot.maximumBytes).contains(Int(sqlite3_column_bytes(statement, 3))),
                  sqlite3_column_type(statement, 4) == SQLITE_INTEGER,
                  [0, 1].contains(sqlite3_column_int(statement, 4)) else {
                throw DatabaseError.operation("Staged text send metadata needs recovery.")
            }
            try requireTextPeerNotRevoked(blob(statement,at:0),generation:generation)
            let payload = blob(statement, at: 3)
            let backup = try decoder.decode(ConversationBackup.self, from: payload)
            guard backup.schemaVersion == 1, backup.memories.isEmpty else { throw ConversationError.invalidBackup }
            let snapshot = try ReviewedTextSnapshot(conversations: backup.conversations, exportedAt: backup.exportedAt)
            // Only canonical bytes produced by staging are valid; unknown JSON
            // fields must not become a hidden unreviewed outgoing payload.
            guard snapshot.data == payload else { throw ConversationError.invalidBackup }
            return StagedTextSend(identity: TextSendIdentity(receiverEpoch: epoch, transfer: id,
                senderCertificateSHA256: blob(statement, at: 5), receiverCertificateSHA256: blob(statement, at: 0), pairingGeneration: generation),
                payload: payload, delivered: sqlite3_column_int(statement, 4) == 1)
        }
    }

    /// Records a receipt only after the native coordinator has authenticated its
    /// peer and bound the receipt to these exact bytes/scope. This API is not proof
    /// of those checks. A socket send completion must NEVER call it by itself.
    func recordTextDeliveryReceipt(identity: TextSendIdentity, payload: Data) throws {
        try Task.checkCancellation()
        guard payload.count <= ReviewedTextSnapshot.maximumBytes else { throw TextSnapshotError.limit }
        try database.execute("BEGIN IMMEDIATE")
        do {
            guard let staged = try textSend(id: identity.transfer), staged.identity == identity,
                  staged.payload == payload else { throw DatabaseError.operation("Text delivery receipt does not match a staged transfer.") }
            try withStatement("UPDATE text_send_outbox SET delivered=1 WHERE transfer=?") { statement in
                bind(identity.transfer.uuidString, to: 1, in: statement); try requireDone(statement)
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    /// Explicit local cancellation/cleanup. Cannot retract bytes already delivered.
    func discardTextSend(id: UUID) throws {
        try withStatement("DELETE FROM text_send_outbox WHERE transfer=?") { statement in
            bind(id.uuidString, to: 1, in: statement); try requireDone(statement)
        }
    }

    /// Merges a complete validated snapshot transactionally. Attachments remain local references.
    @discardableResult
    /// Actor isolation keeps deduplication and the existing transaction contiguous.
    func importMemoryNotes(_ incoming: [MemoryNote]) throws -> BackupImportSummary {
        try Task.checkCancellation()
        guard incoming.count <= ConversationBackup.maximumRecordsPerCollection, incoming.allSatisfy({ $0.content.count <= 4000 && $0.content.utf8.count <= 32_768 }) else {
            throw ConversationError.tooLarge
        }
        let existing = try memories()
        var seen = Set(existing.map(\.content))
        let additions = incoming.filter { seen.insert($0.content).inserted }
        guard existing.count + additions.count <= ConversationBackup.maximumRecordsPerCollection else {
            throw ConversationError.backupRecordLimit
        }
        let data = try encoder.encode(ConversationBackup(conversations: [], memories: additions))
        return try importData(data, policy: .preserveLocal)
    }

    func importData(_ data: Data, policy: BackupImportPolicy = .replaceMatching) throws -> BackupImportSummary {
        try importData(data, policy: policy, receive: nil)
    }

    /// The caller must complete native authentication and exact-payload review first.
    /// No production UI/transport calls this API yet. Only text conversations are accepted;
    /// attachments and memories require separate ownership/consent implementations.
    /// Receipts retain exact bytes (not a homemade hash), bounded to 50 MB in total.
    func receiveReviewedText(_ data: Data, identity: ReviewedTextReceiveIdentity) throws -> BackupImportSummary {
        guard data.count <= 5_000_000, identity.peerCertificateSHA256.count == 32 else {
            throw DatabaseError.operation("Invalid text receive scope or size.")
        }
        return try importData(data, policy: .keepBoth, receive: identity)
    }


    /// Receiver-only exact-base reconciliation. The caller must authenticate the
    /// peer and approve these exact bytes before invoking this dormant boundary.
    /// Committed local edits are protected; an eventual coordinator must also
    /// serialize unsaved UI edits and unconditional local saves with receives.
    func receiveReviewedTextRevisions(_ data: Data, identity: ReviewedTextReceiveIdentity) throws -> TextRevisionReceiveSummary {
        try Task.checkCancellation()
        guard identity.peerCertificateSHA256.count == 32 else { throw DatabaseError.operation("Invalid revision receive identity.") }
        let envelope = try TextRevisionEnvelope.decodeCanonical(data)
        for record in envelope.records {
            try validate(record.incoming)
            if let base = record.base { try validate(base) }
        }
        try database.execute("BEGIN IMMEDIATE")
        do {
            try requireTextPeerNotRevoked(identity.peerCertificateSHA256, generation: identity.pairingGeneration)
            guard try textReceiveEpoch() == identity.epoch else { throw DatabaseError.operation("This revision session predates history erasure.") }
            try withStatement("PRAGMA user_version") { statement in
                guard sqlite3_step(statement) == SQLITE_ROW, [2,3].contains(sqlite3_column_int64(statement, 0)) else {
                    throw DatabaseError.operation("Revision metadata needs recovery; no revision was applied.")
                }
            }
            guard try tableExists("text_revision_lineage") else { throw DatabaseError.operation("Revision lineage is unavailable.") }
            if let prior = try revisionReceipt(data, identity: identity, sources: envelope.records.map { $0.incoming.id }) {
                try database.execute("COMMIT")
                return prior
            }
            try withStatement("SELECT COALESCE(SUM(length(payload)),0),COUNT(*) FROM text_receive_receipts") { statement in
                guard sqlite3_step(statement) == SQLITE_ROW,
                      sqlite3_column_int64(statement, 1) < 10_000,
                      sqlite3_column_int64(statement, 0) <= 50_000_000 - Int64(data.count) else {
                    throw DatabaseError.operation("Receive receipt capacity reached; no revision was applied.")
                }
            }
            var reserved = Set(envelope.records.map { $0.incoming.id })
            func freshID() throws -> UUID {
                while true {
                    let id = UUID()
                    if reserved.contains(id) { continue }
                    let exists = try withStatement("SELECT 1 FROM conversations WHERE id=? UNION ALL SELECT 1 FROM memory WHERE id=? LIMIT 1") { statement in
                        bind(id.uuidString, to: 1, in: statement); bind(id.uuidString, to: 2, in: statement)
                        let step = sqlite3_step(statement)
                        guard step == SQLITE_ROW || step == SQLITE_DONE else { throw DatabaseError.operation("Could not reserve revision identity.") }
                        return step == SQLITE_ROW
                    }
                    if !exists { reserved.insert(id); return id }
                }
            }
            var results: [TextRevisionReceiveSummary.Record] = []
            for record in envelope.records {
                try Task.checkCancellation()
                let sourceID = record.incoming.id
                let incomingBytes = try TextRevisionEnvelope.canonicalConversation(record.incoming)
                let lineage = try revisionLineage(sourceID: sourceID, identity: identity)
                var destination = record.incoming
                var disposition: TextRevisionReceiveSummary.Disposition = .inserted
                var preserved: UUID?
                if let lineage {
                    guard let base = record.base,
                          try TextRevisionEnvelope.canonicalConversation(base) == lineage.remote,
                          let current = try rawRevisionConversation(id: lineage.localID) else {
                        throw DatabaseError.operation("Missing, stale or deleted revision ancestry; no changes were applied.")
                    }
                    // Remote no-op never adopts an unrelated local edit as its base.
                    if incomingBytes == lineage.remote {
                        results.append(.init(sourceID: sourceID, localID: lineage.localID, disposition: .unchanged, preservedLocalID: nil))
                        continue
                    }
                    if try TextRevisionEnvelope.canonicalConversation(current) == lineage.local {
                        destination.id = lineage.localID
                        disposition = .advanced
                    } else {
                        destination.id = try freshID()
                        disposition = .conflict
                        preserved = lineage.localID
                    }
                } else {
                    guard record.base == nil else { throw DatabaseError.operation("Unknown remote ancestry; no changes were applied.") }
                    // First contact cannot claim ownership of an existing local row,
                    // even when its bytes happen to match the incoming conversation.
                    if try rawRevisionConversation(id: sourceID) != nil {
                        destination.id = try freshID()
                        disposition = .conflict
                        preserved = sourceID
                    }
                }
                try writeConversation(destination)
                let localBytes = try TextRevisionEnvelope.canonicalConversation(destination)
                try withStatement("INSERT INTO text_revision_lineage(peer,generation,source,local_id,remote_base,local_base) VALUES(?,?,?,?,?,?) ON CONFLICT(peer,generation,source) DO UPDATE SET local_id=excluded.local_id,remote_base=excluded.remote_base,local_base=excluded.local_base") { statement in
                    bind(identity.peerCertificateSHA256,to:1,in:statement)
                    bind(identity.pairingGeneration.uuidString,to:2,in:statement)
                    bind(sourceID.uuidString,to:3,in:statement)
                    bind(destination.id.uuidString,to:4,in:statement)
                    bind(incomingBytes,to:5,in:statement); bind(localBytes,to:6,in:statement)
                    try requireDone(statement)
                }
                results.append(.init(sourceID:sourceID,localID:destination.id,disposition:disposition,preservedLocalID:preserved))
            }
            try withStatement("SELECT COALESCE(SUM(length(remote_base)+length(local_base)),0),COUNT(*) FROM text_revision_lineage") { statement in
                guard sqlite3_step(statement) == SQLITE_ROW,
                      sqlite3_column_int64(statement,0) <= 50_000_000,
                      sqlite3_column_int64(statement,1) <= 10_000 else {
                    throw DatabaseError.operation("Revision lineage capacity reached; changes rolled back.")
                }
            }
            let summary = TextRevisionReceiveSummary(records: results)
            let canonical = JSONEncoder(); canonical.outputFormatting = .sortedKeys
            try withStatement("INSERT INTO text_receive_receipts(transfer,peer,generation,payload,summary) VALUES(?,?,?,?,?)") { statement in
                bind(identity.transfer.uuidString,to:1,in:statement)
                bind(identity.peerCertificateSHA256,to:2,in:statement)
                bind(identity.pairingGeneration.uuidString,to:3,in:statement)
                bind(data,to:4,in:statement); bind(try canonical.encode(summary),to:5,in:statement)
                try requireDone(statement)
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
            return summary
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    private func rawRevisionConversation(id: UUID) throws -> Conversation? {
        try withStatement("SELECT payload FROM conversations WHERE id=?") { statement in
            bind(id.uuidString,to:1,in:statement)
            let step=sqlite3_step(statement)
            if step == SQLITE_DONE { return nil }
            guard step == SQLITE_ROW, (1...TextRevisionEnvelope.maximumBytes).contains(Int(sqlite3_column_bytes(statement,0))) else {
                throw DatabaseError.operation("Revision target is unavailable or exceeds its bound.")
            }
            let value=try decoder.decode(Conversation.self,from:blob(statement,at:0))
            guard value.id==id else { throw DatabaseError.operation("Revision target identity is inconsistent.") }
            return value
        }
    }

    private func revisionLineage(sourceID: UUID, identity: ReviewedTextReceiveIdentity) throws -> (localID:UUID,remote:Data,local:Data)? {
        try withStatement("SELECT local_id,remote_base,local_base FROM text_revision_lineage WHERE peer=? AND generation=? AND source=?") { statement in
            bind(identity.peerCertificateSHA256,to:1,in:statement)
            bind(identity.pairingGeneration.uuidString,to:2,in:statement)
            bind(sourceID.uuidString,to:3,in:statement)
            let step=sqlite3_step(statement)
            if step == SQLITE_DONE { return nil }
            guard step == SQLITE_ROW, sqlite3_column_type(statement,0)==SQLITE_TEXT, sqlite3_column_bytes(statement,0)==36, let raw=sqlite3_column_text(statement,0),
                  let localID=UUID(uuidString:String(cString:raw)),
                  (1...TextRevisionEnvelope.maximumBytes).contains(Int(sqlite3_column_bytes(statement,1))),
                  (1...TextRevisionEnvelope.maximumBytes).contains(Int(sqlite3_column_bytes(statement,2))) else {
                throw DatabaseError.operation("Revision lineage needs recovery.")
            }
            let remote=blob(statement,at:1),local=blob(statement,at:2)
            let remoteValue=try decoder.decode(Conversation.self,from:remote)
            let localValue=try decoder.decode(Conversation.self,from:local)
            guard remoteValue.id==sourceID,localValue.id==localID,
                  try TextRevisionEnvelope.canonicalConversation(remoteValue)==remote,
                  try TextRevisionEnvelope.canonicalConversation(localValue)==local else {
                throw DatabaseError.operation("Revision lineage is inconsistent.")
            }
            return (localID,remote,local)
        }
    }

    private func revisionReceipt(_ data: Data, identity: ReviewedTextReceiveIdentity, sources: [UUID]) throws -> TextRevisionReceiveSummary? {
        try withStatement("SELECT peer,generation,payload,summary FROM text_receive_receipts WHERE transfer=?") { statement in
            bind(identity.transfer.uuidString,to:1,in:statement)
            let step=sqlite3_step(statement)
            if step == SQLITE_DONE { return nil }
            guard step == SQLITE_ROW,
                  sqlite3_column_type(statement,0)==SQLITE_BLOB,sqlite3_column_bytes(statement,0)==32,
                  sqlite3_column_type(statement,1)==SQLITE_TEXT,sqlite3_column_bytes(statement,1)==36,
                  blob(statement,at:0)==identity.peerCertificateSHA256,
                  let generation=sqlite3_column_text(statement,1),
                  String(cString:generation)==identity.pairingGeneration.uuidString,
                  sqlite3_column_bytes(statement,2)==data.count,
                  blob(statement,at:2)==data,
                  (1...50_000).contains(Int(sqlite3_column_bytes(statement,3))) else {
                throw DatabaseError.operation("Revision transfer identity was reused with different scope or bytes.")
            }
            let bytes=blob(statement,at:3)
            let summary=try decoder.decode(TextRevisionReceiveSummary.self,from:bytes)
            let canonical=JSONEncoder();canonical.outputFormatting = .sortedKeys
            guard summary.records.map(\.sourceID)==sources,try canonical.encode(summary)==bytes else {
                throw DatabaseError.operation("Revision receipt is inconsistent.")
            }
            return summary
        }
    }

    func textReceiveEpoch() throws -> UUID {
        try withStatement("SELECT epoch FROM text_receive_epoch WHERE singleton=1") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let raw = sqlite3_column_text(statement, 0),
                  let epoch = UUID(uuidString: String(cString: raw)) else {
                throw DatabaseError.operation("Receive metadata needs recovery; no transfer was applied.")
            }
            return epoch
        }
    }

    private func importData(_ data: Data, policy: BackupImportPolicy, receive: ReviewedTextReceiveIdentity?) throws -> BackupImportSummary {
        try Task.checkCancellation()
        guard data.count <= ConversationBackup.maximumBytes else { throw ConversationError.tooLarge }
        let backup: ConversationBackup
        do { backup = try decoder.decode(ConversationBackup.self, from: data) }
        catch { throw ConversationError.invalidBackup }
        guard backup.schemaVersion == 1, backup.conversations.count <= ConversationBackup.maximumRecordsPerCollection, backup.memories.count <= ConversationBackup.maximumRecordsPerCollection,
              Set(backup.conversations.map(\.id)).count == backup.conversations.count,
              Set(backup.memories.map(\.id)).count == backup.memories.count else { throw ConversationError.invalidBackup }
        if receive != nil {
            guard backup.memories.isEmpty,
                  backup.conversations.allSatisfy({ $0.messages.allSatisfy { $0.attachments.isEmpty && $0.state != .streaming } }) else {
                throw DatabaseError.operation("This receive operation accepts completed text conversations only.")
            }
        }
        try backup.conversations.forEach(validate)
        try backup.memories.forEach(validateMemory)
        try Task.checkCancellation()
        try database.execute("BEGIN IMMEDIATE")
        do {
            if let receive {
                try requireTextPeerNotRevoked(receive.peerCertificateSHA256,generation:receive.pairingGeneration)
                guard try textReceiveEpoch() == receive.epoch else { throw DatabaseError.operation("This receive session predates local history erasure.") }
                if let prior = try textReceiveReceipt(data, identity: receive) {
                    try database.execute("COMMIT")
                    return prior
                }
                let retained = try withStatement("SELECT COALESCE(SUM(length(payload)),0), COUNT(*) FROM text_receive_receipts") { statement in
                    guard sqlite3_step(statement) == SQLITE_ROW else { throw DatabaseError.operation("Could not inspect receive capacity.") }
                    guard sqlite3_column_int64(statement, 1) < 10_000 else { throw DatabaseError.operation("Receive receipt storage is full; no transfer was applied.") }
                    return sqlite3_column_int64(statement, 0)
                }
                guard retained <= 50_000_000 - Int64(data.count) else { throw DatabaseError.operation("Receive receipt storage is full; no transfer was applied.") }
            }
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
            var copiedConversations = 0
            var copiedMemories = 0
            if policy == .keepBoth {
                let localConversations = try list(includeArchived: true)
                let localMemories = try memories()
                let conversationsByID = Dictionary(uniqueKeysWithValues: localConversations.map { ($0.id, $0) })
                let memoriesByID = Dictionary(uniqueKeysWithValues: localMemories.map { ($0.id, $0) })
                var reservedIDs = Set(localConversations.map(\.id) + localMemories.map(\.id)
                                      + incomingConversations.map(\.id) + incomingMemories.map(\.id))
                func freshID() -> UUID {
                    var id = UUID()
                    while reservedIDs.contains(id) { id = UUID() }
                    reservedIDs.insert(id)
                    return id
                }
                incomingConversations = incomingConversations.compactMap { incoming in
                    guard let local = conversationsByID[incoming.id] else { return incoming }
                    guard local != incoming else { return nil }
                    var copy = incoming
                    copy.id = freshID()
                    copiedConversations += 1
                    return copy
                }
                incomingMemories = incomingMemories.compactMap { incoming in
                    guard let local = memoriesByID[incoming.id] else { return incoming }
                    guard local != incoming else { return nil }
                    var copy = incoming
                    copy.id = freshID()
                    copiedMemories += 1
                    return copy
                }
            }
            // Validate replacements together with untouched rows before changing either table.
            // Do not call save here: intermediate rows may conflict while a consistent batch
            // replaces every reference to an identity, and the transaction is already owned.
            try validateMergedImageIdentities(replacing: incomingConversations)
            for conversation in incomingConversations { try Task.checkCancellation(); try writeConversation(conversation) }
            for note in incomingMemories { try Task.checkCancellation(); try saveMemory(note) }
            try Task.checkCancellation()
            let summary = BackupImportSummary(writtenConversations: incomingConversations.count,
                                       writtenMemories: incomingMemories.count,
                                       skippedConversations: backup.conversations.count - incomingConversations.count,
                                       skippedMemories: backup.memories.count - incomingMemories.count,
                                       copiedConversations: copiedConversations, copiedMemories: copiedMemories)
            if let receive {
                try withStatement("INSERT INTO text_receive_receipts (transfer,peer,generation,payload,summary) VALUES (?,?,?,?,?)") { statement in
                    bind(receive.transfer.uuidString, to: 1, in: statement)
                    bind(receive.peerCertificateSHA256, to: 2, in: statement)
                    bind(receive.pairingGeneration.uuidString, to: 3, in: statement)
                    bind(data, to: 4, in: statement)
                    bind(try encoder.encode(summary), to: 5, in: statement)
                    try requireDone(statement)
                }
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
            return summary
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    private func textReceiveReceipt(_ data: Data, identity: ReviewedTextReceiveIdentity) throws -> BackupImportSummary? {
        try withStatement("SELECT peer,generation,payload,summary FROM text_receive_receipts WHERE transfer=?") { statement in
            bind(identity.transfer.uuidString, to: 1, in: statement)
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW,
                  blob(statement, at: 0) == identity.peerCertificateSHA256,
                  let generation = sqlite3_column_text(statement, 1),
                  String(cString: generation) == identity.pairingGeneration.uuidString,
                  blob(statement, at: 2) == data else {
                throw DatabaseError.operation("Transfer identity was reused with a different scope or payload.")
            }
            return try decoder.decode(BackupImportSummary.self, from: blob(statement, at: 3))
        }
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
            // Message rows use every attachment UUID as an Identifiable key, not only images.
            let attachmentIDs = message.attachments.map(\.id)
            guard Set(attachmentIDs).count == attachmentIDs.count else { throw ConversationError.unsafeAttachment }
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

