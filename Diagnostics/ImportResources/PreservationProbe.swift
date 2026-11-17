import Foundation
import Darwin

@main struct PreservationProbe {
    struct Stage: Codable, Sendable { let phase: String; let bytes: UInt64; let peakRSSBytes: Int64 }
    static func main() async throws {
        guard CommandLine.arguments.count == 2, let bytes = UInt64(CommandLine.arguments[1]), bytes <= 2_200_000_000,
              let temporary = ProcessInfo.processInfo.environment["RUNNER_TEMP"] else { fatalError("Synthetic diagnostic arguments missing") }
        let root = URL(fileURLWithPath: temporary).appendingPathComponent("orivyn-preservation-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic.zip")
        guard FileManager.default.createFile(atPath: source.path, contents: nil) else { fatalError("Cannot create synthetic source") }
        let writer = try FileHandle(forWritingTo: source); try writer.truncate(atOffset: bytes); try writer.close()
        let started = Date()
        let report = try await Task.detached(priority: .utility) {
            var counts: [String: Int] = [:]
            var stages: [Stage] = []
            var previous = ""
            let manifest = try ArchivePreservation.preserve(source: source, staging: root.appendingPathComponent("job")) { phase, completed in
                counts[phase, default: 0] += 1
                if phase != previous {
                    var usage = rusage(); guard getrusage(RUSAGE_SELF, &usage) == 0 else { fatalError("No stage memory measurement") }
                    stages.append(Stage(phase: phase, bytes: completed, peakRSSBytes: Int64(usage.ru_maxrss)))
                    previous = phase
                }
            }
            return (manifest, counts, stages)
        }.value
        var usage = rusage(); guard getrusage(RUSAGE_SELF, &usage) == 0 else { fatalError("No memory measurement") }
        let sourceSize = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.uint64Value
        guard sourceSize == bytes, report.0.bytes == bytes else { fatalError("Source changed") }
        let result: [String: Any] = ["syntheticBytes": bytes, "sha256": report.0.sha256,
            "callbacks": report.1, "stages": try JSONSerialization.jsonObject(with: JSONEncoder().encode(report.2)), "peakRSSBytes": usage.ru_maxrss, "elapsedSeconds": Date().timeIntervalSince(started),
            "originalUnchanged": true, "scope": "macOS synthetic preservation only; not device crash proof"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
