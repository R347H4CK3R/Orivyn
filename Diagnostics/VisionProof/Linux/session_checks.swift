import Foundation

@MainActor final class Lease: VisionLeaseOwner {
    var heavyWorkLease: LocalHeavyWorkLease?
    var releases = 0
    var releaseBlocked = false
    var waiter: CheckedContinuation<Void, Never>?
    func beginHeavyWork(id: UUID, kind: LocalHeavyWorkKind) async throws {
        guard heavyWorkLease == nil else { throw LocalHeavyWorkError.busy }
        heavyWorkLease = .init(id: id, kind: kind, phase: .preparing)
        if releaseBlocked { await withCheckedContinuation { waiter = $0 } }
        try Task.checkCancellation()
        heavyWorkLease?.phase = .ready
    }
    func endHeavyWork(id: UUID) { if heavyWorkLease?.id == id { heavyWorkLease = nil; releases += 1 } }
    func revokeHeavyWork(id: UUID?) { if id == nil || heavyWorkLease?.id == id { heavyWorkLease?.phase = .revoked } }
}
final class Runtime: LocalVisionRuntime, @unchecked Sendable {
    let lock = NSLock()
    var entered = false, cancelled = false, closed = false
    var answer = "Actual answer", releaseOK = true
    var runWait: CheckedContinuation<Void, Never>?
    var closeWait: CheckedContinuation<Void, Never>?
    var blockRun = false, blockClose = false
    func run(encodedImage: Data, question: String) async throws -> String {
        lock.withLock { entered = true }
        if blockRun { await withCheckedContinuation { c in lock.withLock { runWait = c } } }
        return answer
    }
    func cancel() { lock.withLock { cancelled = true } }
    func close() async -> Bool {
        lock.withLock { closed = true }
        if blockClose { await withCheckedContinuation { c in lock.withLock { closeWait = c } } }
        return releaseOK
    }
    func finishRun() { lock.withLock { runWait?.resume(); runWait = nil } }
    func finishClose() { lock.withLock { closeWait?.resume(); closeWait = nil } }
}
@main struct Checks {
    @MainActor static func until(_ condition: () -> Bool) async {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        fatalError("condition timeout")
    }
    @MainActor static func main() async {
        let data = Data([1]), question = "Describe."
        do {
            let owner = Lease(), runtime = Runtime(); owner.releaseBlocked = true
            let session = VisionSession(owner: owner, runtime: runtime)
            let task = Task { await session.run(encodedImage: data, question: question) }
            await until { owner.waiter != nil }
            precondition(!runtime.entered && owner.heavyWorkLease?.phase == .preparing)
            owner.waiter?.resume(); await task.value
            precondition(session.output == "Actual answer" && owner.releases == 1 && runtime.closed)
        }
        do {
            let owner = Lease(), runtime = Runtime(); runtime.blockRun = true; runtime.blockClose = true
            let session = VisionSession(owner: owner, runtime: runtime)
            let task = Task { await session.run(encodedImage: data, question: question) }
            await until { runtime.lock.withLock { runtime.runWait != nil } }
            let closing = Task { await session.close() }
            await until { runtime.lock.withLock { runtime.cancelled } }
            precondition(owner.heavyWorkLease != nil)
            runtime.finishRun()
            await until { runtime.lock.withLock { runtime.closeWait != nil } }
            precondition(owner.heavyWorkLease != nil && session.output == nil)
            runtime.finishClose(); _ = await closing.value; await task.value
            precondition(owner.heavyWorkLease == nil && session.output == nil)
            _ = await session.close(); precondition(owner.releases == 1)
        }
        do {
            let owner = Lease(), runtime = Runtime(); runtime.releaseOK = false
            let session = VisionSession(owner: owner, runtime: runtime)
            await session.run(encodedImage: data, question: question)
            precondition(session.phase == .blocked && owner.heavyWorkLease?.phase == .revoked && session.output == nil)
        }
        do {
            let owner = Lease(), runtime = Runtime(); owner.releaseBlocked = true
            let session = VisionSession(owner: owner, runtime: runtime)
            let task = Task { await session.run(encodedImage: data, question: question) }
            await until { owner.waiter != nil }; task.cancel(); owner.waiter?.resume(); await task.value
            precondition(!runtime.entered && owner.heavyWorkLease == nil && session.output == nil)
        }
        do {
            let owner = Lease(), runtime = Runtime(); runtime.blockRun = true
            let session = VisionSession(owner: owner, runtime: runtime)
            let task = Task { await session.run(encodedImage: data, question: question) }
            await until { runtime.lock.withLock { runtime.runWait != nil } }; owner.revokeHeavyWork(id: session.id); runtime.finishRun(); await task.value
            precondition(session.output == nil && owner.heavyWorkLease == nil)
        }
        do {
            let owner = Lease(), runtime = Runtime(); runtime.answer = " "
            let session = VisionSession(owner: owner, runtime: runtime)
            await session.run(encodedImage: data, question: question)
            precondition(session.output == nil && session.error != nil && owner.heavyWorkLease == nil)
        }
        do {
            let owner = Lease(), runtime = Runtime()
            let session = VisionSession(owner: owner, runtime: runtime)
            await session.run(encodedImage: Data(), question: question)
            precondition(!runtime.entered && runtime.closed && owner.heavyWorkLease == nil)
            await session.run(encodedImage: data, question: question)
            precondition(!runtime.entered)
        }
        // Teardown suspends after an answer exists: never publish before release,
        // nor after cancellation, dismissal, or revocation during that suspension.
        for trigger in 0..<3 {
            let owner = Lease(), runtime = Runtime(); runtime.blockClose = true
            let session = VisionSession(owner: owner, runtime: runtime)
            let task = Task { await session.run(encodedImage: data, question: question) }
            await until { runtime.lock.withLock { runtime.closeWait != nil } }
            precondition(session.output == nil && owner.heavyWorkLease != nil)
            var closeTask: Task<Bool, Never>?
            if trigger == 0 { task.cancel() }
            if trigger == 1 {
                closeTask = Task { await session.close() }
                await until { runtime.lock.withLock { runtime.cancelled } }
            }
            if trigger == 2 { owner.revokeHeavyWork(id: session.id) }
            runtime.finishClose(); await task.value; _ = await closeTask?.value
            precondition(session.output == nil && owner.heavyWorkLease == nil)
        }
        do {
            let owner = Lease(), runtime = Runtime(), other = UUID()
            owner.heavyWorkLease = .init(id: other, kind: .localAgent, phase: .ready)
            let session = VisionSession(owner: owner, runtime: runtime)
            await session.run(encodedImage: data, question: question)
            precondition(!runtime.entered && owner.heavyWorkLease?.id == other && owner.releases == 0)
        }
        do {
            let owner = Lease(), runtime = Runtime(); runtime.answer = String(repeating: "é", count: 8193)
            let session = VisionSession(owner: owner, runtime: runtime)
            await session.run(encodedImage: data, question: question)
            precondition(session.output == nil && session.error != nil)
        }
        print("PASS 12 production VisionSession lifecycle scenarios")
    }
}
