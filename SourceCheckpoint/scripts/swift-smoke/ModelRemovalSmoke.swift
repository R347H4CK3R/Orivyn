import Foundation

// Exact production remove method + transaction; descriptor lookup is a controlled local-file boundary.
actor RemovalStoreScaffold {
    let root: URL
    var installing = false
    init(root: URL) { self.root = root }
    func destination(for descriptor: LocalModelDescriptor) throws -> URL { root.appendingPathComponent(descriptor.fileName) }
    func readManifest() throws -> [LocalModelDescriptor] {
        try JSONDecoder().decode([LocalModelDescriptor].self, from: Data(contentsOf: root.appendingPathComponent("installed-models.json")))
    }
    // PRODUCTION_METHOD
}
@main struct ModelRemovalSmoke {
    enum Failure: Error { case failed(String) }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Model removal failed: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("fixtures")
        var passed = 0
        for scenario in ["stale", "unknown", "valid"] {
            let root = base.appendingPathComponent(scenario)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let current = LocalModelDescriptor(id: "current", name: "Current", fileName: "current.gguf", downloadURL: nil, sha256: String(repeating: "b", count: 64), byteCount: 32, license: "synthetic fixture", sourceURL: nil)
            let file = root.appendingPathComponent(current.fileName), manifest = root.appendingPathComponent("installed-models.json")
            let bytes = Data(repeating: 7, count: 32), metadata = try JSONEncoder().encode([current])
            try bytes.write(to: file); try metadata.write(to: manifest)
            let selected = scenario == "valid" ? current : LocalModelDescriptor(id: scenario == "unknown" ? "missing" : current.id, name: current.name, fileName: current.fileName, downloadURL: nil, sha256: String(repeating: "a", count: 64), byteCount: 32, license: current.license, sourceURL: nil)
            let store = RemovalStoreScaffold(root: root)
            var rejected = false
            do { try await store.remove(selected) } catch { rejected = true }
            if scenario == "valid" {
                guard !rejected, !FileManager.default.fileExists(atPath: file.path), try await store.readManifest().isEmpty else { throw Failure.failed("Valid selection did not delete transactionally") }
            } else {
                guard rejected, FileManager.default.fileExists(atPath: file.path), try Data(contentsOf: file) == bytes,
                      try Data(contentsOf: manifest) == metadata else { throw Failure.failed("\(scenario) selection altered installed bytes or manifest") }
            }
            passed += 1; print("PASS \(scenario) model removal preserves correct identity")
        }
        print("PASS \(passed) exact-method/file-transaction checks; no real model or native store verification")
    }
}
