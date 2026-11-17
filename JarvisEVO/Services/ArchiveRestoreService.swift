import Foundation
import ArchiveExtraction
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Serialized preparation under a canonical app-private jobs root. The caller
/// holds Files-provider coordination throughout prepare, and serializes each job.
/// This service never activates history or deletes originals. The SQLite receipt,
/// not this filesystem status, is authoritative after committing history.
enum ArchiveRestoreService {
    enum Failure: LocalizedError {
        case invalidJob, unsafePath, limit, integrity, missingConversations, io
        var errorDescription: String? {
            switch self {
            case .limit: return "This export exceeds a safe processing limit. Try a smaller export. Existing chat history has not been replaced."
            case .missingConversations: return "This archive does not contain a supported conversations file."
            case .invalidJob: return "This restore job is no longer valid. Select the archive again."
            case .unsafePath: return "The archive contains an unsafe file path and cannot be imported."
            case .integrity: return "Archive verification failed. No unverified content will be imported."
            case .io: return "The restore files could not be read or saved. Check available storage and file access."
            }
        }
    }
    struct Review: Codable, Sendable, Equatable {
        let jobID: UUID
        var conversationCount = 0; var messageCount = 0; var unresolvedCount = 0
        var omittedCount = 0; var retainedFileCount = 0; var archiveSHA256 = ""
    }
    struct Unresolved: Codable, Sendable { let messageID: UUID; let source: String; let originalJSON: Data }
    struct Plan: Codable, Sendable {
        let expectedEpoch: UUID
        var conversations: [Conversation] = []
        var unresolved: [Unresolved] = []
    }
    private struct FileRecord: Codable { let path: String; let bytes: UInt64; let sha256: String }
    private struct State: Codable {
        let version: Int; let jobID: UUID; var phase: String
        var original: ArchivePreservation.Manifest?
        var review: Review?; var planSHA256: String?; var inventorySHA256: String?
        var events: [String] = []
    }
    static func prepare(source: URL, jobsRoot: URL, expectedEpoch: UUID,
                        progress: @Sendable (String) -> Void = { _ in }) throws -> Review {
        try validateRoot(jobsRoot); try Task.checkCancellation()
        let id = UUID(), job = jobsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        guard mkdir(job.path, 0o700) == 0 else { throw Failure.io }
        try flushDirectory(jobsRoot)
        var state = State(version: 1, jobID: id, phase: "copying")
        func record(_ phase: String, _ event: String) throws {
            state.phase = phase; state.events.append("\(Date().timeIntervalSince1970) \(event)")
            state.events = Array(state.events.suffix(200))
            try writeJSON(state, to: job.appendingPathComponent("state.json"), maximum: 262_144)
            progress(event)
        }
        do {
            try record("copying", "Preserving original ZIP. Existing history is unchanged.")
            let payload = job.appendingPathComponent("payload", isDirectory: true)
            state.original = try ArchivePreservation.preserve(source: source, staging: payload) { stage, bytes in
                progress("\(stage): \(bytes) bytes processed")
            }
            try record("extracting", "Original verified. Validating and extracting ZIP entries.")
            let extracted = payload.appendingPathComponent("extracted", isDirectory: true)
            let entries = try ZIPExtractor.extract(source: payload.appendingPathComponent("original.zip"), destination: extracted)
            try flushDirectory(payload)
            try record("planning", "Extracted \(entries.count) entries. Verifying retained files.")
            var inventory: [FileRecord] = []
            for entry in entries where !entry.path.hasSuffix("/") {
                try Task.checkCancellation()
                let digest = try hashRegular(try safeChild(extracted, entry.path), maximum: 4_000_000_000)
                guard digest.bytes == entry.bytes else { throw Failure.integrity }
                inventory.append(FileRecord(path: entry.path, bytes: digest.bytes, sha256: digest.sha256))
                if inventory.count % 25 == 0 { progress("Verified \(inventory.count) retained files") }
            }
            let candidates = inventory.filter { URL(fileURLWithPath: $0.path).lastPathComponent == "conversations.json" }
            guard candidates.count == 1, let candidate = candidates.first, let original = state.original else { throw Failure.missingConversations }
            let handle = try openRegular(try safeChild(extracted, candidate.path), maximum: 1_000_000_000)
            defer { try? handle.close() }
            var plan = Plan(expectedEpoch: expectedEpoch), seen = Set<UUID>(), budget = 0
            var review = Review(jobID: id); review.archiveSHA256 = original.sha256; review.retainedFileCount = inventory.count
            _ = try ChatGPTRecordStream.read(handle) { bytes in
                func convertRecord() throws -> ChatGPTConversationRestore.Result {
                    let projected = try ChatGPTRecordProjection.project(bytes)
                    let identities = try legacyIdentities(projected, archiveSHA: original.sha256)
                    return try ChatGPTConversationRestore.convert(projected: projected, identities: identities)
                }
                #if canImport(ObjectiveC)
                let converted = try autoreleasepool(invoking: convertRecord)
                #else
                let converted = try convertRecord()
                #endif
                review.omittedCount += converted.omittedMessages
                if let conversation = converted.conversation {
                    guard seen.insert(conversation.id).inserted else { throw Failure.integrity }
                    budget += try JSONEncoder().encode(conversation).count
                    guard budget <= 40_000_000 else { throw Failure.limit }
                    plan.conversations.append(conversation); review.messageCount += conversation.messages.count
                }
                for asset in converted.unresolvedContent {
                    budget += asset.originalJSON.count
                    guard budget <= 40_000_000, plan.unresolved.count < 20_000 else { throw Failure.limit }
                    plan.unresolved.append(Unresolved(messageID: asset.messageID, source: asset.source, originalJSON: asset.originalJSON))
                }
                progress("Prepared \(plan.conversations.count) conversations and \(review.messageCount) visible messages")
            }
            try Task.checkCancellation()
            review.conversationCount = plan.conversations.count; review.unresolvedCount = plan.unresolved.count
            try writeJSON(plan, to: job.appendingPathComponent("plan.json"), maximum: 50_000_000)
            try writeJSON(inventory, to: job.appendingPathComponent("inventory.json"), maximum: 32_000_000)
            state.planSHA256 = try hashRegular(job.appendingPathComponent("plan.json"), maximum: 50_000_000).sha256
            state.inventorySHA256 = try hashRegular(job.appendingPathComponent("inventory.json"), maximum: 32_000_000).sha256
            state.review = review
            _ = try ArchivePreservation.revalidate(staging: payload, expected: original)
            try record("reviewReady", "Preparation verified. Review before importing; unsupported assets remain preserved and unlinked.")
            return review
        } catch {
            // Acknowledged cancellation never discards originals or marks readiness.
            try? record(Task.isCancelled ? "cancelled" : "failed", "Preparation stopped. Retained files remain available; no history was imported.")
            throw error
        }
    }
    struct RecoveryReport: Sendable { let reviews: [Review]; let incompleteJobs: [UUID] }
    static func listReadyReviews(jobsRoot: URL) throws -> [Review] { try inspectRetainedJobs(jobsRoot: jobsRoot).reviews }
    static func inspectRetainedJobs(jobsRoot: URL) throws -> RecoveryReport {
        try validateRoot(jobsRoot)
        let urls = try FileManager.default.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil)
        guard urls.count <= 1000 else { throw Failure.limit }
        var result: [Review] = [], incomplete: [UUID] = []
        for url in urls {
            try Task.checkCancellation()
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            do {
                let state = try readState(job: url)
                guard state.jobID == id else { throw Failure.integrity }
                if state.phase == "reviewReady", let review = state.review, review.jobID == id { result.append(review) }
                else if state.phase != "committed" { incomplete.append(id) }
            } catch is CancellationError { throw CancellationError() }
            catch { incomplete.append(id) }
        }
        return RecoveryReport(reviews: result.sorted { $0.jobID.uuidString < $1.jobID.uuidString }, incompleteJobs: incomplete)
    }
    /// Discoverable read-only inventories include committed preparations. This
    /// deliberately does not change recovery/ready-to-commit eligibility.
    static func listInventoryReviews(jobsRoot: URL) throws -> [Review] {
        try validateRoot(jobsRoot)
        let urls = try FileManager.default.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil)
        guard urls.count <= 1000 else { throw Failure.limit }
        var reviews: [Review] = []
        for url in urls {
            try Task.checkCancellation()
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            do {
                func readReview() throws -> Review? {
                    let state = try readState(job: url)
                    guard state.jobID == id, ["reviewReady", "committed"].contains(state.phase),
                          let review = state.review, review.jobID == id,
                          let original = state.original, original.sha256 == review.archiveSHA256,
                          state.planSHA256 != nil else { return nil }
                    return review
                }
                #if canImport(ObjectiveC)
                let review = try autoreleasepool(invoking: readReview)
                #else
                let review = try readReview()
                #endif
                if let review { reviews.append(review) }
            } catch is CancellationError { throw CancellationError() }
            catch { continue } // Damaged jobs are reported by the existing recovery path.
        }
        return reviews.sorted { $0.jobID.uuidString < $1.jobID.uuidString }
    }

    /// Validates the prepared-plan binding only, not retained asset existence or
    /// SQLite activation. No raw JSON, inferred path, or original file is exposed.
    static func retainedInventory(review: Review, jobsRoot: URL, offset: Int = 0) throws -> ArchiveRestoreInventory.Page {
        try validateRoot(jobsRoot); try Task.checkCancellation()
        let job = jobsRoot.appendingPathComponent(review.jobID.uuidString), state = try readState(job: job)
        guard state.jobID == review.jobID, ["reviewReady", "committed"].contains(state.phase),
              state.review == review, let original = state.original,
              original.sha256 == review.archiveSHA256, let expectedHash = state.planSHA256 else { throw Failure.invalidJob }
        guard (0...10_000).contains(review.conversationCount), (0...500_000).contains(review.messageCount),
              (0...20_000).contains(review.unresolvedCount) else { throw Failure.limit }
        let planURL = job.appendingPathComponent("plan.json")
        func buildPage() throws -> ArchiveRestoreInventory.Page {
            let bytes = try readBounded(planURL, maximum: 50_000_000)
            guard digest(bytes) == expectedHash else { throw Failure.integrity }
            let plan = try JSONDecoder().decode(Plan.self, from: bytes)
            guard plan.conversations.count == review.conversationCount, plan.unresolved.count == review.unresolvedCount,
                  plan.conversations.reduce(0, { $0 + $1.messages.count }) == review.messageCount else { throw Failure.integrity }
            return try ArchiveRestoreInventory.page(conversations: plan.conversations,
                references: plan.unresolved.map { .init(messageID: $0.messageID, source: $0.source) }, offset: offset)
        }
        #if canImport(ObjectiveC)
        let page = try autoreleasepool(invoking: buildPage)
        #else
        let page = try buildPage()
        #endif
        let current = try readState(job: job)
        guard current.jobID == state.jobID, current.phase == state.phase, current.review == review,
              current.original == original, current.planSHA256 == expectedHash,
              try hashRegular(planURL, maximum: 50_000_000).sha256 == expectedHash else { throw Failure.integrity }
        try Task.checkCancellation(); return page
    }

    static func verifyForCommit(review: Review, jobsRoot: URL,
                                progress: @Sendable (String) -> Void = { _ in }) throws -> Plan {
        try validateRoot(jobsRoot)
        let job = jobsRoot.appendingPathComponent(review.jobID.uuidString), state = try readState(job: job)
        guard state.jobID == review.jobID, state.phase == "reviewReady", state.review == review,
              let original = state.original, original.sha256 == review.archiveSHA256 else { throw Failure.invalidJob }
        progress("Rechecking preserved original before import")
        _ = try ArchivePreservation.revalidate(staging: job.appendingPathComponent("payload"), expected: original)
        let planURL = job.appendingPathComponent("plan.json"), inventoryURL = job.appendingPathComponent("inventory.json")
        let planBytes = try readBounded(planURL, maximum: 50_000_000)
        let inventoryBytes = try readBounded(inventoryURL, maximum: 32_000_000)
        guard digest(planBytes) == state.planSHA256, digest(inventoryBytes) == state.inventorySHA256 else { throw Failure.integrity }
        let inventory = try JSONDecoder().decode([FileRecord].self, from: inventoryBytes)
        guard inventory.count == review.retainedFileCount, inventory.count <= 20_000 else { throw Failure.integrity }
        let extracted = job.appendingPathComponent("payload/extracted")
        for (index, file) in inventory.enumerated() {
            let hash = try hashRegular(try safeChild(extracted, file.path), maximum: 4_000_000_000)
            guard hash.bytes == file.bytes, hash.sha256 == file.sha256 else { throw Failure.integrity }
            if index % 25 == 0 { progress("Reverified \(index + 1)/\(inventory.count) retained files") }
        }
        guard try hashRegular(planURL, maximum: 50_000_000).sha256 == state.planSHA256,
              try hashRegular(inventoryURL, maximum: 32_000_000).sha256 == state.inventorySHA256 else { throw Failure.integrity }
        let plan = try JSONDecoder().decode(Plan.self, from: planBytes)
        guard plan.conversations.count == review.conversationCount,
              plan.conversations.reduce(0, { $0 + $1.messages.count }) == review.messageCount,
              plan.unresolved.count == review.unresolvedCount else { throw Failure.integrity }
        try Task.checkCancellation(); return plan
    }
    /// Call only AFTER SQLite returns a durable receipt. A failure here does not
    /// undo that receipt; callers must report committed/reload-pending, not retry blindly.
    static func markCommitted(review: Review, jobsRoot: URL) throws {
        try validateRoot(jobsRoot)
        let job = jobsRoot.appendingPathComponent(review.jobID.uuidString)
        var state = try readState(job: job)
        guard state.review == review else { throw Failure.integrity }
        state.phase = "committed"; state.events.append("\(Date().timeIntervalSince1970) SQLite receipt committed")
        try writeJSON(state, to: job.appendingPathComponent("state.json"), maximum: 262_144)
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func legacyIdentities(_ record: [String: Any], archiveSHA: String) throws -> [String: UUID] {
        guard let id = record["id"] as? String else { throw Failure.integrity }
        var keys = ["conversation:" + id]
        if let mapping = record["mapping"] as? [String: [String: Any]] {
            for node in mapping.values {
                if let message = node["message"] as? [String: Any], let messageID = message["id"] as? String {
                    keys.append(ChatGPTConversationRestore.legacyMessageKey(conversationID: id, messageID: messageID))
                }
            }
        }
        var result: [String: UUID] = [:]
        for key in keys {
            var digest = Array(SHA256.hash(data: Data((archiveSHA + "|" + key).utf8)).prefix(16))
            digest[6] = (digest[6] & 15) | 128; digest[8] = (digest[8] & 63) | 128
            let text = digest.map { String(format: "%02x", $0) }.joined()
            let value = "\(text.prefix(8))-\(text.dropFirst(8).prefix(4))-\(text.dropFirst(12).prefix(4))-\(text.dropFirst(16).prefix(4))-\(text.dropFirst(20))"
            guard let uuid = UUID(uuidString: value) else { throw Failure.integrity }; result[key] = uuid
        }
        return result
    }
    private static func validateRoot(_ url: URL) throws {
        guard url.isFileURL, url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else { throw Failure.unsafePath }
        var value = stat(); guard lstat(url.path, &value) == 0, value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.unsafePath }
    }
    private static func safeChild(_ root: URL, _ relative: String) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.contains("\\"), !relative.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw Failure.unsafePath }
        let url = root.appendingPathComponent(relative)
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else { throw Failure.unsafePath }; return url
    }
    private static func openRegular(_ url: URL, maximum: UInt64) throws -> FileHandle {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else { throw Failure.unsafePath }
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_size >= 0, UInt64(value.st_size) <= maximum else { close(fd); throw Failure.limit }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    private static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        let handle = try openRegular(url, maximum: UInt64(maximum)); defer { try? handle.close() }
        var result = Data()
        while let bytes = try ArchiveReadBuffer.read(handle, upToCount: 65_536), !bytes.isEmpty {
            try Task.checkCancellation(); guard result.count <= maximum - bytes.count else { throw Failure.limit }; result.append(bytes)
        }
        return result
    }
    private static func hashRegular(_ url: URL, maximum: UInt64) throws -> (bytes: UInt64, sha256: String) {
        let handle = try openRegular(url, maximum: maximum); defer { try? handle.close() }
        var hash = SHA256(), size: UInt64 = 0
        while let bytes = try ArchiveReadBuffer.read(handle, upToCount: 65_536), !bytes.isEmpty {
            try Task.checkCancellation(); guard size <= maximum, UInt64(bytes.count) <= maximum - size else { throw Failure.limit }
            size += UInt64(bytes.count); hash.update(data: bytes)
        }
        return (size, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    private static func readState(job: URL) throws -> State {
        try validateRoot(job)
        let state = try JSONDecoder().decode(State.self, from: readBounded(job.appendingPathComponent("state.json"), maximum: 262_144))
        guard state.version == 1 else { throw Failure.invalidJob }; return state
    }
    private static func writeJSON<T: Encodable>(_ value: T, to url: URL, maximum: Int) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value); guard data.count <= maximum else { throw Failure.limit }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.io }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        try handle.write(contentsOf: data); guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else { throw Failure.io }
        try flushDirectory(url.deletingLastPathComponent())
    }
    private static func flushDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io }; defer { close(fd) }
        guard fsync(fd) == 0 else { throw Failure.io }
    }
}
