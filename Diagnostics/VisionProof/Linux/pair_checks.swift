import Foundation
actor Files: VisionPairFileStore {
    var installed = Set<String>()
    var downloads = 0
    var blocked = false
    var waiter: CheckedContinuation<Void, Never>?
    enum Missing: Error { case file }
    func verify(_ artifact: VisionModelArtifact) async throws -> URL {
        if blocked { await withCheckedContinuation { waiter = $0 } }
        guard installed.contains(artifact.name) else { throw Missing.file }
        return URL(fileURLWithPath: "/private-models/" + artifact.name)
    }
    func download(_ artifact: VisionModelArtifact, progress: @escaping @Sendable (Double) -> Void) {
        downloads += 1; installed.insert(artifact.name); progress(1)
    }
    func setBlocked() { blocked = true }
    func ready() -> Bool { waiter != nil }
    func unblock() { blocked = false; waiter?.resume(); waiter = nil }
}
@main struct Checks {
    static func main() async throws {
        precondition(VisionModelPair.totalBytes < 2_000_000_000)
        let files = Files(), store = VisionPairStore(files: Files())
        do { _ = try await store.acquire(); fatalError("missing pair admitted") } catch { }
        let installed = VisionPairStore(files: files)
        try await installed.install { _ in }
        let count = await files.downloads; precondition(count == 2)
        let lease = try await installed.acquire()
        do { try await installed.install { _ in }; fatalError("active pair replaced") } catch { }
        do { _ = try await installed.acquire(); fatalError("overlap admitted") } catch { }
        await installed.release(lease)
        try await installed.install { _ in }
        let repeatedCount = await files.downloads; precondition(repeatedCount == 2)
        await files.setBlocked()
        let task = Task { try await installed.acquire() }
        for _ in 0..<10000 { if await files.ready() { break }; await Task.yield() }
        do { _ = try await installed.acquire(); fatalError("verification overlap admitted") } catch { }
        task.cancel(); await files.unblock()
        do { _ = try await task.value; fatalError("cancelled acquire admitted") } catch { }
        let after = try await installed.acquire()
        await installed.release(lease) // a stale prior owner cannot release this pair
        do { _ = try await installed.acquire(); fatalError("stale owner released new pair") } catch { }
        await installed.release(after)
        // Uniform pixel rejection is based only on observed channel ranges.
        for rgb in [Data(repeating: 255, count: 12),Data(repeating: 0,count:12),Data([255,0,0,255,0,0,255,0,0,255,0,0]),Data([255,255,255,253,254,255,255,255,255,255,255,255])] {
            do { try VisionPixelBoundary.validate(width:2,height:2,rgb:rgb); fatalError("blank admitted") } catch { }
        }
        try VisionPixelBoundary.validate(width:2,height:1,rgb:Data([255,255,255,252,255,255]))
        do { try VisionPixelBoundary.validate(width:Int.max,height:1,rgb:Data());fatalError("dimensions") } catch { }
        print("PASS pair integrity admission/active replacement/cancellation and pixel boundaries")
    }
}
