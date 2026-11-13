import CryptoKit
import Foundation

/// Stores weights inside Application Support, outside backups. Installation is atomic:
/// partial, cancelled, incorrect-sized and incorrect-hash downloads are never selectable.
actor LocalModelStore {
    static let maximumFileBytes: Int64 = 2_000_000_000
    private let root: URL
    private let fileManager = FileManager.default
    private var installing = false

    init(root: URL? = nil) throws {
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("JarvisEVO/Models", isDirectory: true)
        self.root = base
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var mutableURL = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
        try ModelInstallTransaction.recover(root: base)
    }

    func installedModels() throws -> [LocalModelDescriptor] {
        try readManifest().filter { isInstalled($0) }
    }

    /// Cheap UI check only. Every inference load calls verifiedURL and hashes all bytes.
    func isInstalled(_ descriptor: LocalModelDescriptor) -> Bool {
        guard let url = try? destination(for: descriptor),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value == descriptor.byteCount
    }

    func verifiedURL(for descriptor: LocalModelDescriptor) async throws -> URL {
        let url = try destination(for: descriptor)
        guard fileManager.fileExists(atPath: url.path) else { throw LocalModelError.notInstalled }
        let (size, digest) = try inspect(url)
        guard size == descriptor.byteCount, digest == descriptor.sha256.lowercased() else {
            throw LocalModelError.integrityMismatch
        }
        return url
    }

    func download(_ descriptor: LocalModelDescriptor, policy: ModelDownloadPolicy = .userInitiated, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard !installing else { throw LocalModelError.busy }
        let target = try destination(for: descriptor)
        guard let source = descriptor.downloadURL, source.scheme?.lowercased() == "https", source.user == nil, source.password == nil else { throw LocalModelError.insecureURL }
        try checkStorage(required: descriptor.byteCount * 2)
        installing = true
        defer { installing = false }
        let configuration = policy.configuration()
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = ModelDownloadProgress(expectedBytes: descriptor.byteCount, progress: progress)
        progress(0)
        let (temporaryURL, response) = try await session.download(from: source, delegate: delegate)
        defer { try? fileManager.removeItem(at: temporaryURL) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocalModelError.downloadFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard response.url?.scheme?.lowercased() == "https" else { throw LocalModelError.insecureURL }
        try Task.checkCancellation()
        let (size, hash) = try inspect(temporaryURL)
        guard size == descriptor.byteCount, hash == descriptor.sha256.lowercased() else { throw LocalModelError.integrityMismatch }
        try install(temporaryURL, descriptor: descriptor, target: target)
        progress(1)
    }

    /// Import does not assert publisher authenticity. The computed digest detects later
    /// corruption; the user is responsible for the source and license of imported models.
    func importModel(from source: URL) async throws -> LocalModelDescriptor {
        guard !installing else { throw LocalModelError.busy }
        installing = true
        defer { installing = false }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let staged = root.appendingPathComponent(".import-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staged) }
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= Self.maximumFileBytes else { throw LocalModelError.tooLarge }
        try checkStorage(required: size.int64Value * 2)
        try Task.checkCancellation()
        try fileManager.copyItem(at: source, to: staged)
        let (byteCount, hash) = try inspect(staged)
        let id = "imported-\(UUID().uuidString.lowercased())"
        let descriptor = LocalModelDescriptor(id: id, name: source.deletingPathExtension().lastPathComponent, fileName: "\(id).gguf", downloadURL: nil, sha256: hash, byteCount: byteCount, license: "User-provided · verify model license", sourceURL: nil)
        try install(staged, descriptor: descriptor, target: destination(for: descriptor))
        return descriptor
    }

    func remove(_ descriptor: LocalModelDescriptor) throws {
        guard !installing else { throw LocalModelError.busy }
        let url = try destination(for: descriptor)
        var manifest = try readManifest()
        manifest.removeAll { $0.id == descriptor.id }
        let manifestData = try JSONEncoder().encode(manifest)
        // Preserve recovery copies until both deletion and metadata publication commit.
        // If backup allocation fails, no live files have changed.
        try ModelInstallTransaction.remove(root: root, targetName: url.lastPathComponent,
            manifest: manifestData, prepareFile: { stagedManifest in
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: stagedManifest.path)
            })
    }

    private func destination(for descriptor: LocalModelDescriptor) throws -> URL {
        try ModelInstallTransaction.recover(root: root)
        let filename = descriptor.fileName
        guard !descriptor.id.isEmpty, filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.contains("/"), !filename.contains("\\"), filename.hasSuffix(".gguf"),
              descriptor.byteCount >= 24, descriptor.sha256.count == 64,
              descriptor.sha256.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw LocalModelError.invalidDescriptor }
        guard descriptor.byteCount <= Self.maximumFileBytes else { throw LocalModelError.tooLarge }
        let url = root.appendingPathComponent(filename)
        // Reject symlinks, including ones that resolve outside this model store.
        if fileManager.fileExists(atPath: url.path), try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw LocalModelError.invalidDescriptor
        }
        return url
    }

    private func inspect(_ url: URL) throws -> (Int64, String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 8) ?? Data()
        guard header.count == 8, Array(header.prefix(4)) == [0x47, 0x47, 0x55, 0x46],
              [UInt8(2), UInt8(3)].contains(header[4]), header[5...7].allSatisfy({ $0 == 0 }) else { throw LocalModelError.invalidGGUF }
        var hasher = SHA256()
        hasher.update(data: header)
        var count = Int64(header.count)
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            count += Int64(data.count)
            guard count <= Self.maximumFileBytes else { throw LocalModelError.tooLarge }
            hasher.update(data: data)
        }
        guard count >= 24 else { throw LocalModelError.invalidGGUF }
        return (count, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private func install(_ temporaryURL: URL, descriptor: LocalModelDescriptor, target: URL) throws {
        try Task.checkCancellation()
        // Prepare/encode metadata before touching any published model bytes.
        var manifest = try readManifest()
        manifest.removeAll { $0.id == descriptor.id }
        manifest.append(descriptor)
        let manifestData = try JSONEncoder().encode(manifest)
        let oldBytes = (try? fileManager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
        try checkStorage(required: descriptor.byteCount + oldBytes)
        try ModelInstallTransaction.commit(root: root, targetName: target.lastPathComponent,
            source: temporaryURL, manifest: manifestData, prepareFile: { url in
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            })
    }

    private var manifestURL: URL { root.appendingPathComponent("installed-models.json") }
    private func readManifest() throws -> [LocalModelDescriptor] {
        try ModelInstallTransaction.recover(root: root)
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        return try JSONDecoder().decode([LocalModelDescriptor].self, from: Data(contentsOf: manifestURL))
    }
    func availableStorageBytes() -> Int64? {
        try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    private func checkStorage(required: Int64) throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < required + 100_000_000 {
            throw LocalModelError.insufficientStorage
        }
    }
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedBytes: Int64
    private let progress: @Sendable (Double) -> Void
    init(expectedBytes: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.expectedBytes = expectedBytes
        self.progress = progress
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Prevent oversized responses from silently consuming unbounded storage.
        if totalBytesWritten > expectedBytes { downloadTask.cancel(); return }
        progress(min(0.99, Double(totalBytesWritten) / Double(expectedBytes)))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}
