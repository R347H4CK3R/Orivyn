import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
/// Synthetic host probe only. No ZIP extraction, SQLite or device claim.
@main struct ImportResourceProbe {
    enum Failure: Error { case wrongResult, missingRejection, peakExceeded, resourceMeasurement }
    static func peak() throws -> Int64 {
        var usage = rusage()
        #if canImport(Darwin)
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw Failure.resourceMeasurement }; return Int64(usage.ru_maxrss)
        #else
        guard getrusage(Int32(RUSAGE_SELF.rawValue), &usage) == 0 else { throw Failure.resourceMeasurement }; return Int64(usage.ru_maxrss) * 1024
        #endif
    }
    static func main() throws {
        let args = CommandLine.arguments
        let input = URL(fileURLWithPath: args[1]), mode = args[2]
        let handle = try FileHandle(forReadingFrom: input); defer { try? handle.close() }
        let expectedText = "Synthetic visible message" + (["many", "longstream"].contains(mode) ? String(repeating: "x", count: mode == "longstream" ? 50_000 : 2000) : "")
        var visible = 0, rejected = false
        do {
            _ = try ChatGPTRecordStream.read(handle) { data in
                func convert() throws {
                    let projected = try ChatGPTRecordProjection.project(data)
                    let result = try ChatGPTConversationRestore.convert(projected: projected, identities: [:])
                    guard result.conversation?.messages.map(\.content) == [expectedText] else { throw Failure.wrongResult }
                    visible += 1
                }
                #if canImport(ObjectiveC)
                try autoreleasepool(invoking: convert)
                #else
                try convert()
                #endif
            }
        } catch let error as ChatGPTRecordProjection.Failure {
            if ["dense", "many", "longstream"].contains(mode) { throw error }
            guard !error.localizedDescription.isEmpty else { throw Failure.wrongResult }
            rejected = true
            print("EXPECTED_REJECTION \(error.localizedDescription)")
        }
        if ["dense", "many", "longstream"].contains(mode) { guard visible == (["many", "longstream"].contains(mode) ? 10_000 : 1) else { throw Failure.wrongResult } }
        else { guard rejected && visible == 0 else { throw Failure.missingRejection } }
        let rss = try peak()
        guard rss < 256 * 1024 * 1024 else { throw Failure.peakExceeded }
        print("PASS mode=\(mode) visible=\(visible) peakBytes=\(rss) ceilingBytes=268435456")
    }
}
