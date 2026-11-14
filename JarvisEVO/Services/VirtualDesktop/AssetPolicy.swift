import Foundation
import CryptoKit
import CoreFoundation
import Darwin

struct VMAsset: Sendable { let name: String; let bytes: Int; let sha256: String; let mime: String }
enum VMPolicyError: Error { case rejected }

struct VMAssetStore: Sendable {
    static func acceptedSize(_ asset: VMAsset) -> Bool {
        if asset.name == "maintained.img" {
            return asset.bytes == 135266304 && asset.sha256 == "78418639ecd90573da211b62a502334f569f029b913525f50601b09d928b244d" && asset.mime == "application/octet-stream"
        }
        return asset.bytes > 0 && asset.bytes <= 12 * 1024 * 1024
    }
    private let assets: [String: Data]
    init(root: URL, catalog: [VMAsset] = VMAssetCatalog.files) throws {
        guard root.isFileURL, (try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])).isSymbolicLink != true,
              (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true,
              catalog.count <= 16, Set(catalog.map(\.name)).count == catalog.count else { throw VMPolicyError.rejected }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var contents: [String: Data] = [:]
        for asset in catalog {
            guard asset.name.range(of: "^[a-zA-Z0-9.-]+$", options: .regularExpression) != nil,
                  !asset.name.hasPrefix("."), Self.acceptedSize(asset) else { throw VMPolicyError.rejected }
            let url = canonicalRoot.appendingPathComponent(asset.name)
            let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard fd >= 0 else { throw VMPolicyError.rejected }
            let data: Data
            do {
                defer { Darwin.close(fd) }
                var info = stat()
                guard Darwin.fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
                      info.st_size == Int64(asset.bytes) else { throw VMPolicyError.rejected }
                var bytes = [UInt8](repeating: 0, count: asset.bytes + 1)
                var count = 0
                while count < bytes.count {
                    let readCount = bytes.withUnsafeMutableBytes { pointer in Darwin.read(fd, pointer.baseAddress!.advanced(by: count), pointer.count - count) }
                    if readCount < 0 { if errno == EINTR { continue }; throw VMPolicyError.rejected }
                    if readCount == 0 { break }; count += readCount
                }
                guard count == asset.bytes else { throw VMPolicyError.rejected }
                data = Data(bytes.prefix(count))
            }
            guard SHA256.hash(data: data).map({String(format: "%02x", $0)}).joined() == asset.sha256 else { throw VMPolicyError.rejected }
            contents["/" + asset.name] = data
        }
        guard contents.values.reduce(0, {$0 + $1.count}) <= 160 * 1024 * 1024 else { throw VMPolicyError.rejected }
        assets = contents
    }
    static func allowedPath(_ request: URLRequest) -> String? {
        guard request.httpMethod == nil || request.httpMethod == "GET", let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "orivyn-vm", parts.host == "bundle", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.query == nil,
              parts.percentEncodedPath == parts.path,
              VMAssetCatalog.files.contains(where: { "/" + $0.name == parts.path }) else { return nil }
        if let fragment = parts.fragment, !(parts.path == "/index.html" && UUID(uuidString: fragment) != nil) { return nil }
        return parts.path
    }
    func response(for request: URLRequest) throws -> (Data, String) {
        guard let path = Self.allowedPath(request), let data = assets[path],
              let item = VMAssetCatalog.files.first(where: { "/" + $0.name == path }) else { throw VMPolicyError.rejected }
        return (data, item.mime)
    }
}

struct VMStatus: Equatable {
    enum Event: String { case ready, running, paused, stopped, error, diagnostic }
    let event: Event
    let instructions: UInt64
    let diagnostic: String?
    static func parse(_ body: Any, owner: UUID) -> Self? {
        guard let value = body as? [String: Any], (Set(value.keys) == ["version", "owner", "event", "instructions"] || Set(value.keys) == ["version", "owner", "event", "instructions", "diagnostic"]),
              let version = value["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let ownerText = value["owner"] as? String, ownerText.count == 36, UUID(uuidString: ownerText) == owner,
              let name = value["event"] as? String, let event = Event(rawValue: name),
              let count = value["instructions"] as? NSNumber, CFGetTypeID(count) != CFBooleanGetTypeID(),
              count.doubleValue.isFinite, count.doubleValue >= 0, count.doubleValue <= 9_007_199_254_740_991,
              count.doubleValue.rounded(.down) == count.doubleValue else { return nil }
        let diagnostic = value["diagnostic"] as? String
        if event == .diagnostic {
            guard let diagnostic, !diagnostic.isEmpty, diagnostic.utf8.count <= 1024, diagnostic.count <= 256, count.uint64Value == 0 else { return nil }
        } else if value["diagnostic"] != nil { return nil }
        return Self(event: event, instructions: count.uint64Value, diagnostic: diagnostic)
    }
}
