import Foundation
import CryptoKit

/// Explicit read target only, never a URL or permission to execute source.
/// Deliberately supports a conservative ASCII branch/tag subset and full commit IDs.
enum RepositoryInspectionReference {
    static func resolve(_ requested: String, defaultBranch: String) -> String? {
        if requested.isEmpty {
            // Preserve existing default-branch support, including Unicode names.
            guard !defaultBranch.isEmpty, defaultBranch.utf8.count <= 512,
                  !defaultBranch.contains(".."), !defaultBranch.contains("\\"),
                  defaultBranch.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
                  defaultBranch.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
            return defaultBranch
        }
        let value = requested
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._/".utf8)
        guard !value.isEmpty, value.utf8.count <= 512,
              value.utf8.allSatisfy({ allowed.contains($0) }), !value.contains(".."),
              value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(".") && !$0.hasSuffix(".lock")
              }) else { return nil }
        return value
    }
    static func isCommit(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct RepositoryInspectionEntry: Sendable, Equatable, Identifiable {
    let path: String
    let blobSHA: String
    let size: Int
    var id: String { path }
}
struct RepositoryInspectionSnapshot: Sendable, Identifiable {
    let id: UUID
    let branch: String
    let commitSHA: String
    let treeSHA: String
    let files: [RepositoryInspectionEntry]
    let omittedFiles: Int
}
struct RepositoryInspectionFile: Sendable {
    let path: String
    let commitSHA: String
    let blobSHA: String
    let text: String
}
enum RepositoryInspectionError: Error, LocalizedError, Equatable {
    case reference, credentials, cancelled, repositoryMismatch, response, bounds, selection, integrity, notText, denied, unavailable, network
    var errorDescription: String? {
        switch self {
        case .reference: "Enter a branch, tag or full lowercase commit ID using letters, numbers, hyphens, underscores, dots and slashes. Leave blank for the default branch."
        case .credentials: "Enter a GitHub token for this session. It is not saved."
        case .cancelled: "Repository inspection was canceled or replaced."
        case .repositoryMismatch: "GitHub did not return the expected private Orivyn repository."
        case .response: "GitHub returned an unexpected response. No source was accepted."
        case .bounds: "This repository response exceeds the inspection limit or is incomplete."
        case .selection: "Choose a file from the current pinned repository snapshot."
        case .integrity: "Source bytes did not match the pinned Git blob identity."
        case .notText: "This blob is not supported UTF-8 source text."
        case .denied: "GitHub denied this request. Check repository access, token permissions, or rate limits."
        case .unavailable: "The requested private repository object is not available to this token."
        case .network: "The GitHub request could not be completed. No server details or credentials are shown."
        }
    }
}

/// Read-only, fixed-destination inspection. Source is untrusted display data, never code,
/// a model prompt, or permission to act. Credentials live only in this actor/request memory.
/// The reused ephemeral transport rejects every redirect and bounds streamed response bytes.
actor RepositoryInspectionClient {
    static let repository = "R347H4CK3R/Orivyn"
    private static let api = "https://api.github.com/repos/" + repository
    private static let maximumFileBytes = 131_072
    private let transport: any MCPHTTPTransport
    private var token: String?
    private var generation = UUID()
    private var pinned: RepositoryInspectionSnapshot?
    private var pending: [UUID: Task<MCPHTTPResponse, any Error>] = [:]

    init(token: String, transport: any MCPHTTPTransport = URLSessionMCPTransport()) throws {
        guard (8...512).contains(token.utf8.count), token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw RepositoryInspectionError.credentials
        }
        self.token = token; self.transport = transport
    }
    /// Call on background/dismissal. Invalidates selected files and cancels in-flight work.
    func clearCredentials() {
        token = nil; generation = UUID(); pinned = nil
        for task in pending.values { task.cancel() }
        pending.removeAll()
    }
    func loadSnapshot(reference requestedReference: String = "") async throws -> RepositoryInspectionSnapshot {
        guard token != nil else { throw RepositoryInspectionError.credentials }
        guard requestedReference.isEmpty || RepositoryInspectionReference.resolve(requestedReference, defaultBranch: "") != nil else {
            throw RepositoryInspectionError.reference
        }
        generation = UUID(); let owner = generation; pinned = nil
        for task in pending.values { task.cancel() }
        pending.removeAll()
        do {
            let repo: Repo = try await get(Self.api, owner: owner, maximum: 65_536)
            guard repo.fullName.lowercased() == Self.repository.lowercased(), repo.isPrivate else {
                throw RepositoryInspectionError.repositoryMismatch
            }
            guard let reference = RepositoryInspectionReference.resolve(requestedReference, defaultBranch: repo.defaultBranch),
                  let branch = reference.addingPercentEncoding(withAllowedCharacters: Self.segmentCharacters) else {
                throw RepositoryInspectionError.response
            }
            let commit: Commit = try await get(Self.api + "/commits/" + branch, owner: owner, maximum: 1_048_576)
            guard Self.validSHA(commit.sha), Self.validSHA(commit.commit.tree.sha) else { throw RepositoryInspectionError.response }
            if RepositoryInspectionReference.isCommit(reference), commit.sha != reference {
                throw RepositoryInspectionError.integrity
            }
            let tree: Tree = try await get(Self.api + "/git/trees/" + commit.commit.tree.sha + "?recursive=1", owner: owner, maximum: 1_048_576)
            guard tree.sha == commit.commit.tree.sha else { throw RepositoryInspectionError.integrity }
            guard !tree.truncated, tree.tree.count <= 4096 else { throw RepositoryInspectionError.bounds }
            var paths = Set<String>(), files: [RepositoryInspectionEntry] = [], omitted = 0
            for entry in tree.tree {
                guard Self.validPath(entry.path), Self.validSHA(entry.sha), paths.insert(entry.path).inserted else {
                    throw RepositoryInspectionError.response
                }
                guard entry.type == "blob", ["100644", "100755"].contains(entry.mode) else {
                    if entry.type != "tree" { omitted += 1 }
                    continue
                }
                guard let size = entry.size, size >= 0 else { throw RepositoryInspectionError.response }
                guard size <= Self.maximumFileBytes else { omitted += 1; continue }
                files.append(RepositoryInspectionEntry(path: entry.path, blobSHA: entry.sha, size: size))
            }
            try check(owner)
            let snapshot = RepositoryInspectionSnapshot(id: UUID(), branch: reference, commitSHA: commit.sha,
                treeSHA: tree.sha, files: files.sorted { $0.path < $1.path }, omittedFiles: omitted)
            pinned = snapshot
            return snapshot
        } catch { throw Self.redacted(error) }
    }
    func readFile(path: String, snapshotID: UUID) async throws -> RepositoryInspectionFile {
        guard token != nil else { throw RepositoryInspectionError.credentials }
        guard let snapshot = pinned, snapshot.id == snapshotID,
              let entry = snapshot.files.first(where: { $0.path == path }) else { throw RepositoryInspectionError.selection }
        let owner = generation
        do {
            let blob: Blob = try await get(Self.api + "/git/blobs/" + entry.blobSHA, owner: owner, maximum: 262_144)
            guard blob.sha == entry.blobSHA, blob.size == entry.size else { throw RepositoryInspectionError.integrity }
            guard blob.encoding == "base64", (0...Self.maximumFileBytes).contains(blob.size), blob.content.utf8.count <= 200_000 else {
                throw RepositoryInspectionError.bounds
            }
            let encoded = blob.content.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            guard let bytes = Data(base64Encoded: encoded), bytes.count == entry.size else { throw RepositoryInspectionError.integrity }
            var gitObject = Data("blob \(bytes.count)\0".utf8); gitObject.append(bytes)
            let hash = Insecure.SHA1.hash(data: gitObject).map { String(format: "%02x", $0) }.joined()
            guard hash == entry.blobSHA else { throw RepositoryInspectionError.integrity }
            guard let text = String(data: bytes, encoding: .utf8), text.unicodeScalars.allSatisfy({
                $0.value >= 32 && $0.value != 127 || [9, 10, 13].contains($0.value)
            }) else { throw RepositoryInspectionError.notText }
            try check(owner)
            return RepositoryInspectionFile(path: entry.path, commitSHA: snapshot.commitSHA, blobSHA: entry.blobSHA, text: text)
        } catch { throw Self.redacted(error) }
    }
    private func check(_ owner: UUID) throws {
        try Task.checkCancellation()
        guard token != nil else { throw RepositoryInspectionError.credentials }
        guard generation == owner else { throw RepositoryInspectionError.cancelled }
    }
    private func get<T: Decodable>(_ address: String, owner: UUID, maximum: Int) async throws -> T {
        try check(owner)
        guard let token, let url = URL(string: address), url.scheme == "https", url.host == "api.github.com",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else { throw RepositoryInspectionError.response }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Orivyn-ReadOnly-Inspection", forHTTPHeaderField: "User-Agent")
        let id = UUID(), transport = self.transport
        let task = Task { [transport, request] in try await transport.send(request, maximumResponseBytes: maximum, timeout: 30) }
        pending[id] = task
        defer { pending[id] = nil }
        let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try check(owner)
        guard response.url == url else { throw RepositoryInspectionError.response }
        guard response.body.count <= maximum else { throw RepositoryInspectionError.bounds }
        switch response.statusCode {
        case 200: break
        case 401, 403, 429: throw RepositoryInspectionError.denied
        case 404: throw RepositoryInspectionError.unavailable
        default: throw RepositoryInspectionError.response
        }
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw RepositoryInspectionError.response }
    }
    private static let segmentCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private static func validSHA(_ value: String) -> Bool { value.utf8.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private static func validPath(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 1024 && !value.contains("\\") && value.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
            && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func redacted(_ error: any Error) -> RepositoryInspectionError {
        if let value = error as? RepositoryInspectionError { return value }
        if error is CancellationError { return .cancelled }
        if let failure = error as? MCPClientFailure {
            switch failure.code {
            case .cancelled: return .cancelled
            case .redirect, .invalidResponse: return .response
            case .responseTooLarge: return .bounds
            default: break
            }
        }
        return .network
    }
    private struct Repo: Decodable {
        let fullName: String; let isPrivate: Bool; let defaultBranch: String
        enum CodingKeys: String, CodingKey { case fullName = "full_name", isPrivate = "private", defaultBranch = "default_branch" }
    }
    private struct Commit: Decodable {
        let sha: String; let commit: Body
        struct Body: Decodable { let tree: Object }
        struct Object: Decodable { let sha: String }
    }
    private struct Tree: Decodable {
        let sha: String; let truncated: Bool; let tree: [Entry]
        struct Entry: Decodable { let path: String; let type: String; let mode: String; let sha: String; let size: Int? }
    }
    private struct Blob: Decodable { let sha: String; let size: Int; let encoding: String; let content: String }
}

