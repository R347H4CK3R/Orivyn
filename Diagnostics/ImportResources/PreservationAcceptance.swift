import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@main struct PreservationAcceptance {
    enum Failure: Error { case invalidArguments, integrity, memory, measurement }
    static func main() async throws {
        guard CommandLine.arguments.count == 3, let bytes = UInt64(CommandLine.arguments[1]), bytes <= 2_200_000_000,
              let temporary = ProcessInfo.processInfo.environment["RUNNER_TEMP"] else { throw Failure.invalidArguments }
        let cancel = CommandLine.arguments[2] == "cancel"
        let root = URL(fileURLWithPath: temporary).appendingPathComponent("synthetic-preserve-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic.zip"), staging = root.appendingPathComponent("job")
        guard FileManager.default.createFile(atPath: source.path, contents: nil) else { throw Failure.integrity }
        let writer = try FileHandle(forWritingTo: source); try writer.truncate(atOffset: bytes); try writer.close()
        let mailbox = ArchiveRestoreProgress()
        let output = try await Task.detached(priority: .utility) { () -> (String, Int) in
            var callbacks = 0
            do {
                let value = try ArchivePreservation.preserve(source: source, staging: staging) { phase, completed in
                    callbacks += 1; mailbox.report("\(phase) \(completed)")
                    if cancel && completed >= 1_048_576 { throw CancellationError() }
                }
                guard !cancel, value.bytes == bytes,
                      try ArchivePreservation.revalidate(staging: staging, expected: value) == value else { throw Failure.integrity }
                return (value.sha256, callbacks)
            } catch is CancellationError {
                guard cancel, FileManager.default.fileExists(atPath: staging.appendingPathComponent("original.zip").path),
                      !FileManager.default.fileExists(atPath: staging.appendingPathComponent("verified-manifest.json").path) else { throw Failure.integrity }
                return ("cancelled-with-partial-retained", callbacks)
            }
        }.value
        mailbox.finish(); var displayed = 0
        for await _ in mailbox.stream { displayed += 1 }
        guard displayed == 1, (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.uint64Value == bytes else { throw Failure.integrity }
        if !cancel && bytes == 2_200_000_000 { guard output.0 == "5a937555b4853ad95365d9b319cf96579dfd4264b20bffb6d3745bea02adf31d" else { throw Failure.integrity } }
        var usage = rusage()
        #if canImport(Darwin)
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw Failure.measurement }
        let peak = Int64(usage.ru_maxrss)
        #else
        guard getrusage(Int32(RUSAGE_SELF.rawValue), &usage) == 0 else { throw Failure.measurement }
        let peak = Int64(usage.ru_maxrss) * 1024
        #endif
        guard peak < 64 * 1024 * 1024 else { throw Failure.memory }
        print("PASS bytes=\(bytes) cancelled=\(cancel) callbacks=\(output.1) pendingDisplayValues=\(displayed) peakBytes=\(peak) sha256=\(output.0)")
    }
}
