import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Local archive excerpts, never model instructions or verified personal facts.
enum FolderMemoryImport {
    struct Review: Sendable {
        var notes: [MemoryNote] = []
        var scanned = 0
        var skipped = 0
        var issues: [String] = []
        var issueCount = 0
        mutating func skip(_ reason: String) {
            skipped += 1; issueCount += 1
            if issues.count < 100 { issues.append(reason) }
        }
    }
    enum Failure: LocalizedError {
        case unreadable, limit, format, missingCurrentNode, invalidTree
        var errorDescription: String? {
            switch self {
            case .unreadable: "The selected folder or file could not be read safely. Download it in Files and try again."
            case .limit: "This import exceeds 20,000 entries, 16 MB per text file/conversation, 1 GB of streamed JSON, 40 MB of extracted text, or 10,000 notes. No notes were imported. Choose a smaller subfolder or split the export."
            case .format: "This is not a supported ChatGPT conversations.json export or UTF-8 text file."
            case .missingCurrentNode: "This conversation export does not identify its selected branch (current_node). It was not imported; a current ChatGPT export is required."
            case .invalidTree: "This conversation export contains a cyclic branch, missing referenced node, or invalid parent. It was not imported."
            }
        }
    }
    /// Callers may reduce these budgets, never expand the production ceilings.
    struct Limits: Sendable {
        var entries = 20_000
        var notes = 10_000
        var textBytes = 40_000_000
    }
    static let fileLimit = 16_000_000
    static let textLimit = 40_000_000
    static let noteLimit = 10_000

    static func additions(_ notes: [MemoryNote], existing: [MemoryNote]) -> [MemoryNote] {
        var seen = Set(existing.map(\.content))
        return notes.filter { seen.insert($0.content).inserted }
    }

    static func notes(text: String, source: String) throws -> [MemoryNote] {
        guard text.utf8.count <= textLimit else { throw Failure.limit }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let label = String(source.prefix(160)).replacingOccurrences(of: "\n", with: " ")
        var result: [MemoryNote] = []
        var position = text.startIndex
        while position < text.endIndex {
            try Task.checkCancellation()
            let end = text.index(position, offsetBy: 3600, limitedBy: text.endIndex) ?? text.endIndex
            let content = "[Imported archive: \(label); part \(result.count + 1)]\n" + text[position..<end]
            // A Character can contain arbitrarily many Unicode scalars.
            guard content.utf8.count <= 32_768 else { throw Failure.limit }
            result.append(MemoryNote(content: content))
            guard result.count <= noteLimit else { throw Failure.limit }
            position = end
        }
        return result
    }

    static func chatGPT(_ data: Data) throws -> [MemoryNote] {
        guard data.count <= fileLimit else { throw Failure.limit }
        guard let conversations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw Failure.format }
        var result: [MemoryNote] = []; var bytes = 0
        for conversation in conversations {
            try Task.checkCancellation()
            let conversationMetadata = conversation["metadata"] as? [String: Any]
            if conversation["is_do_not_remember"] as? Bool == true || conversationMetadata?["is_do_not_remember"] as? Bool == true { continue }
            guard let mapping = conversation["mapping"] as? [String: [String: Any]] else { throw Failure.format }
            let title = String((conversation["title"] as? String ?? "Untitled conversation").prefix(100))
            // A ChatGPT export is a tree, not a chronological message list. Only
            // the current node's ancestry is visible history; sibling alternatives
            // must never be silently combined into supposedly consistent memory.
            // Legacy exports without a selected leaf are rejected, not guessed.
            guard let current = conversation["current_node"] as? String, !current.isEmpty else { throw Failure.missingCurrentNode }
            var branch: [[String: Any]] = [], visited = Set<String>(), cursor: String? = current
            while let id = cursor {
                try Task.checkCancellation()
                guard visited.insert(id).inserted, let node = mapping[id] else { throw Failure.invalidTree }
                branch.append(node)
                if node["parent"] is NSNull { cursor = nil }
                else if let parent = node["parent"] as? String, !parent.isEmpty { cursor = parent }
                else { throw Failure.invalidTree }
            }
            for node in branch.reversed() {
                try Task.checkCancellation()
                guard let message = node["message"] as? [String: Any] else { continue }
                let metadata = message["metadata"] as? [String: Any]
                guard message["is_do_not_remember"] as? Bool != true,
                      metadata?["is_do_not_remember"] as? Bool != true,
                      metadata?["is_visually_hidden_from_conversation"] as? Bool != true,
                      metadata?["is_user_system_message"] as? Bool != true,
                      let author = message["author"] as? [String: Any], let role = author["role"] as? String,
                      ["user", "assistant"].contains(role) else { continue }
                if role == "assistant" {
                    let channel = message["channel"] as? String
                    let recipient = message["recipient"] as? String
                    guard channel == nil || channel == "final",
                          recipient == nil || recipient == "all" else { continue }
                }
                guard let content = message["content"] as? [String: Any],
                      let contentType = content["content_type"] as? String,
                      ["text", "multimodal_text"].contains(contentType),
                      let parts = content["parts"] as? [Any] else { continue }
                let text = parts.compactMap { $0 as? String }.joined(separator: "\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let chunks = try notes(text: role + ": " + text, source: "conversations.json / " + title)
                bytes += chunks.reduce(0) { $0 + $1.content.utf8.count }
                guard bytes <= textLimit, result.count + chunks.count <= noteLimit else { throw Failure.limit }
                result += chunks
            }
        }
        return result
    }

    /// Incrementally parse a top-level array, retaining one conversation at a time.
    /// Metadata/media entries are not promoted into memory. Malformed input aborts review.
    static func streamChatGPT(_ handle: FileHandle, progress: @Sendable (String) -> Void = { _ in }) throws -> [MemoryNote] {
        var phase = 0 // 0 array start; 1 value; 2 object; 3 separator; 4 end
        var mayClose = true, quoted = false, escaped = false
        var depth = 0, sourceBytes = 0, noteBytes = 0, records = 0
        var object = Data(), result: [MemoryNote] = []
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            sourceBytes += chunk.count
            guard sourceBytes <= 1_000_000_000 else { throw Failure.limit }
            for byte in chunk {
                let whitespace = byte == 32 || byte == 9 || byte == 10 || byte == 13
                switch phase {
                case 0:
                    if whitespace { continue }
                    guard byte == 91 else { throw Failure.format }
                    phase = 1
                case 1:
                    if whitespace { continue }
                    if byte == 93 && mayClose { phase = 4; continue }
                    guard byte == 123 else { throw Failure.format }
                    object = Data([byte]); depth = 1; quoted = false; escaped = false; phase = 2
                case 2:
                    object.append(byte)
                    guard object.count <= fileLimit - 2 else { throw Failure.limit }
                    if quoted {
                        if escaped { escaped = false }
                        else if byte == 92 { escaped = true }
                        else if byte == 34 { quoted = false }
                    } else {
                        if byte == 34 { quoted = true }
                        else if byte == 123 || byte == 91 { depth += 1 }
                        else if byte == 125 || byte == 93 { depth -= 1 }
                    }
                    if depth == 0 {
                        var wrapped = Data([91]); wrapped.append(object); wrapped.append(93)
                        let notes = try chatGPT(wrapped)
                        noteBytes += notes.reduce(0) { $0 + $1.content.utf8.count }
                        guard noteBytes <= textLimit, result.count + notes.count <= noteLimit else { throw Failure.limit }
                        result += notes; records += 1; object.removeAll(keepingCapacity: false)
                        phase = 3
                    }
                case 3:
                    if whitespace { continue }
                    if byte == 44 { phase = 1; mayClose = false }
                    else if byte == 93 { phase = 4 }
                    else { throw Failure.format }
                default:
                    guard whitespace else { throw Failure.format }
                }
            }
            if sourceBytes % 1_048_576 < 65_536 { progress("Read \(sourceBytes / 1_048_576) MB · \(records) conversations · \(result.count) notes prepared") }
        }
        try Task.checkCancellation()
        guard phase == 4 else { throw Failure.format }
        return result
    }

    static func scan(_ root: URL, limits: Limits = Limits(), progress: @Sendable (String) -> Void = { _ in }) throws -> Review {
        try Task.checkCancellation()
        guard root.isFileURL else { throw Failure.unreadable }
        guard (1...20_000).contains(limits.entries), (1...noteLimit).contains(limits.notes), (1...textLimit).contains(limits.textBytes) else { throw Failure.limit }
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw Failure.unreadable }
        defer { close(rootFD) }
        var enumerationErrors = 0
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in enumerationErrors += 1; return true }) else { throw Failure.unreadable }
        var review = Review(); var bytes = 0
        for case let url as URL in files {
            try Task.checkCancellation()
            review.scanned += 1
            guard review.scanned <= limits.entries else { throw Failure.limit }
            let relative = String(url.path.dropFirst(root.path.hasSuffix("/") ? root.path.count : root.path.count + 1))
            if review.scanned == 1 || review.scanned % 25 == 0 { progress("Inspecting \(review.scanned): \(url.lastPathComponent)") }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { files.skipDescendants(); review.skip("\(relative): symbolic link skipped"); continue }
            if values.isDirectory == true { continue }
            let ext = url.pathExtension.lowercased()
            let isChat = url.lastPathComponent == "conversations.json"
            guard isChat || ["txt", "md"].contains(ext) else { review.skipped += 1; continue }
            // Common credential files are not useful conversational memory.
            let name = url.lastPathComponent.lowercased()
            guard !["password", "recovery-code", "secret", "credential"].contains(where: name.contains) else { review.skip("\(relative): possible credential file skipped"); continue }
            do {
                let handle = try openRelative(rootFD: rootFD, path: relative)
                defer { try? handle.close() }
                let imported: [MemoryNote]
                if isChat { imported = try streamChatGPT(handle, progress: progress) }
                else {
                    let data = try readBounded(handle)
                    guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw Failure.format }
                    imported = try notes(text: text, source: relative)
                }
                bytes += imported.reduce(0) { $0 + $1.content.utf8.count }
                guard bytes <= limits.textBytes, review.notes.count + imported.count <= limits.notes else { throw Failure.limit }
                review.notes += imported
            } catch Failure.limit { throw Failure.limit }
            catch is CancellationError { throw CancellationError() }
            catch { review.skip("\(relative): \(error.localizedDescription)") }
        }
        for _ in 0..<enumerationErrors { review.skip("A folder entry was unavailable.") }
        review.notes = additions(review.notes, existing: [])
        return review
    }

    /// Open every path component relative to the selected directory without following links.
    private static func openRelative(rootFD: Int32, path: String) throws -> FileHandle {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(".."), !components.contains(".") else { throw Failure.unreadable }
        var fd = dup(rootFD)
        guard fd >= 0 else { throw Failure.unreadable }
        defer { close(fd) }
        for (index, component) in components.enumerated() {
            let next = openat(fd, component, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (index < components.count - 1 ? O_DIRECTORY : 0))
            guard next >= 0 else { throw Failure.unreadable }
            close(fd); fd = next
        }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw Failure.unreadable }
        let owned = dup(fd)
        guard owned >= 0 else { throw Failure.unreadable }
        return FileHandle(fileDescriptor: owned, closeOnDealloc: true)
    }

    private static func readBounded(_ handle: FileHandle) throws -> Data {
        var data = Data()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: min(65_536, fileLimit - data.count + 1)), !chunk.isEmpty else { break }
            guard chunk.count <= fileLimit - data.count else { throw Failure.limit }
            data += chunk
        }
        return data
    }
}
