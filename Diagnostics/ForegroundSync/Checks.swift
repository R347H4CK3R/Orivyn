import Foundation

@MainActor
final class ManualClock {
    var delays: [UInt64] = []
    var pending: [CheckedContinuation<Void, Error>] = []
    func sleep(_ delay: UInt64) async throws {
        delays.append(delay)
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func advance() { if !pending.isEmpty { pending.removeFirst().resume() } }
    func fail() { if !pending.isEmpty { pending.removeFirst().resume(throwing: ClockFailure()) } }
    struct ClockFailure: Error {}
}

@MainActor
final class OperationProbe {
    var seen: [ForegroundSyncCoordinator.Authorization] = []
    var pending: [CheckedContinuation<ForegroundSyncCoordinator.Outcome, Never>] = []
    var immediate: ForegroundSyncCoordinator.Outcome?
    func run(_ auth: ForegroundSyncCoordinator.Authorization) async -> ForegroundSyncCoordinator.Outcome {
        seen.append(auth)
        if let immediate { return immediate }
        return await withCheckedContinuation { pending.append($0) }
    }
    func complete(_ outcome: ForegroundSyncCoordinator.Outcome = .success) {
        pending.removeFirst().resume(returning: outcome)
    }
}

@main
struct Checks {
    @MainActor static func settle() async { for _ in 0..<100 { await Task.yield() } }
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
    @MainActor static func auth() -> ForegroundSyncCoordinator.Authorization {
        .init(peerCertificateSHA256: Data(repeating: 1, count: 32),
              localCertificateSHA256: Data(repeating: 2, count: 32),
              consentRevision: UUID(), pairingGeneration: UUID(), receiverEpoch: UUID(),
              approvedSourceIDs: [UUID()])
    }
    @MainActor static func enabled(_ a: ForegroundSyncCoordinator.Authorization) -> ForegroundSyncCoordinator.Conditions {
        .init(enabled: true, foreground: true, protectedDataAvailable: true, authorization: a)
    }
    @MainActor static func main() async {
        var checks = 0
        // Fail-closed initial/invalid authority and all three lifecycle gates.
        for gate in 0..<5 {
            let p = OperationProbe(), c = ManualClock()
            let s = ForegroundSyncCoordinator(sleep: { try await c.sleep($0) }, operation: { await p.run($0) })
            var state = enabled(auth())
            switch gate {
            case 0: state.enabled = false
            case 1: state.foreground = false
            case 2: state.protectedDataAvailable = false
            case 3: state.authorization = nil
            default: state.authorization = .init(peerCertificateSHA256: Data(),
                localCertificateSHA256: Data(), consentRevision: UUID(),
                pairingGeneration: UUID(), receiverEpoch: UUID(), approvedSourceIDs: [])
            }
            s.update(state)
            await settle()
            expect(p.seen.isEmpty, "ineligible operation started")
            checks += 1
        }
        // A transport deliberately ignores cancellation until completed: no
        // duplicate operation may start after rapid pause/resume or scope edits.
        for gate in 0..<5 {
            let p = OperationProbe(), c = ManualClock()
            let s = ForegroundSyncCoordinator(sleep: { try await c.sleep($0) }, operation: { await p.run($0) })
            let original = enabled(auth())
            s.update(original)
            await settle()
            expect(p.seen.count == 1, "initial transfer absent")
            var stopped = original
            switch gate {
            case 0: stopped.enabled = false
            case 1: stopped.foreground = false
            case 2: stopped.protectedDataAvailable = false
            case 3: stopped.authorization = nil
            default: stopped.authorization = auth()
            }
            s.update(stopped)
            s.update(original)
            await settle()
            expect(p.seen.count == 1 && s.status == .draining, "overlapping transfer")
            p.complete()
            await settle()
            expect(p.seen.count == 2 && c.delays.isEmpty, "stale completion scheduled work")
            s.update(.init())
            p.complete()
            await settle()
            expect(s.status == .stopped, "stop failed")
            checks += 1
        }
        // Successful foreground polling is clock-driven and never duplicates.
        do {
            let p = OperationProbe(), c = ManualClock()
            p.immediate = .success
            let s = ForegroundSyncCoordinator(sleep: { try await c.sleep($0) }, operation: { await p.run($0) })
            let state = enabled(auth())
            s.update(state); await settle()
            s.update(state); await settle()
            expect(p.seen.count == 1 && c.delays == [30_000_000_000], "poll cadence")
            c.advance(); await settle()
            expect(p.seen.count == 2, "poll absent")
            s.update(.init()); c.advance(); await settle()
            expect(p.seen.count == 2 && s.status == .stopped, "sleep cancellation")
            checks += 1
        }
        // Four attempts maximum, 2/5/15s backoff, no lifecycle retry reset.
        do {
            let p = OperationProbe(), c = ManualClock()
            p.immediate = .retryableFailure
            let s = ForegroundSyncCoordinator(sleep: { try await c.sleep($0) }, operation: { await p.run($0) })
            let state = enabled(auth())
            s.update(state); await settle()
            for _ in 0..<3 { c.advance(); await settle() }
            expect(p.seen.count == 4 && c.delays == [2_000_000_000, 5_000_000_000, 15_000_000_000], "retry policy")
            expect(s.status == .retryLimitReached, "retry limit")
            var paused = state; paused.foreground = false
            s.update(paused); s.update(state); await settle()
            expect(p.seen.count == 4 && s.status == .retryLimitReached, "lifecycle reset retry budget/status")
            s.retry(); await settle()
            expect(p.seen.count == 5, "explicit retry absent")
            s.update(.init()); c.advance(); await settle()
            checks += 1
        }
        // Security/conflict failures and broken clocks never retry implicitly.
        for clockFailure in [false, true] {
            let p = OperationProbe(), c = ManualClock()
            p.immediate = clockFailure ? .success : .blocked
            let s = ForegroundSyncCoordinator(sleep: { try await c.sleep($0) }, operation: { await p.run($0) })
            let state = enabled(auth())
            s.update(state); await settle()
            if clockFailure { c.fail(); await settle() }
            expect(s.status == .blocked && p.seen.count == 1, "blocked failure retried")
            s.update(state); await settle()
            expect(p.seen.count == 1, "blocked operation restarted")
            s.update(.init())
            checks += 1
        }
        print("Foreground sync coordinator: \(checks) checks passed")
    }
}
