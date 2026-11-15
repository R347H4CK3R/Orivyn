import Foundation
import Network

@available(macOS 15.0, *)
@MainActor
enum NativeAutomaticSyncChecks {
    struct Result: Codable {
        let name: String
        let passed: Bool
        let sourceCount: Int
        let receivedCount: Int
        let reusedPendingTransfer: Bool
    }

    static func run(root: URL, password: String, output: URL) async throws {
        let a = try FixtureIdentity(root: root, name: "a", password: password)
        let b = try FixtureIdentity(root: root, name: "b", password: password)
        var results: [Result] = []
        for mode in ["automatic-send", "pending-retry", "snapshot-outside-scope", "revoked-sender", "idle-then-edit", "local-busy"] {
            let directory = root.appendingPathComponent("automatic-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sender = try SQLiteConversationStore(url: directory.appendingPathComponent("sender.sqlite"))
            let receiver = try SQLiteConversationStore(url: directory.appendingPathComponent("receiver.sqlite"))
            var source = Conversation(title: "Synthetic automatic exchange")
            let other = Conversation(title: "Unapproved synthetic record")
            try await sender.save(source)
            try await sender.save(other)
            let epoch = try await receiver.textReceiveEpoch(), generation = UUID()
            let sendAuth = ForegroundSyncCoordinator.Authorization(peerCertificateSHA256: a.pin,
                localCertificateSHA256: b.pin, consentRevision: UUID(), pairingGeneration: generation,
                receiverEpoch: epoch, approvedSourceIDs: [source.id])
            let receiveAuth = ForegroundSyncCoordinator.Authorization(peerCertificateSHA256: b.pin,
                localCertificateSHA256: a.pin, consentRevision: UUID(), pairingGeneration: generation,
                receiverEpoch: epoch, approvedSourceIDs: [source.id])
            var pendingID: UUID?
            if mode == "pending-retry" {
                let reviewed = try await sender.exportTextSnapshot(ids: [source.id])
                let staged = try await sender.stageTextRevisionSend(reviewed,
                    senderCertificateSHA256: b.pin, peerCertificateSHA256: a.pin,
                    pairingGeneration: generation, receiverEpoch: epoch)
                pendingID = staged.identity.transfer
            }
            if mode == "revoked-sender" {
                try await sender.revokeTextPeer(peerCertificateSHA256: a.pin, pairingGeneration: generation)
            }
            let ports = AsyncStream<NWEndpoint.Port>.makeStream()
            var listenerCreations = 0
            let incoming = PeerAutomaticSyncController(store: receiver, route: .receive(.any),
                currentAuthorization: { receiveAuth },
                makeProbe: { _ in
                    listenerCreations += 1
                    return PeerTLSProbe(pair: try .init(identity: a.identity,
                        scannedPeerSHA256: b.pin, peerCertificateDER: b.der, generation: generation),
                        timeoutSeconds: mode == "idle-then-edit" && listenerCreations <= 5 ? 0.1 : 30)
                },
                snapshot: { _ in throw GateError.failed("receiver must not export") },
                receive: { auth, channel in
                    // This harness has no AppModel; production must inject its
                    // exclusive history ownership boundary instead.
                    _ = try await PeerTextRevisionExchange.receive(approvedSourceIDs: auth.approvedSourceIDs,
                        expectedEpoch: auth.receiverEpoch, store: receiver, over: channel)
                },
                listenerReady: { ports.continuation.yield($0) })
            incoming.update(.init(enabled: true, foreground: true, protectedDataAvailable: true, authorization: receiveAuth))
            var iterator = ports.stream.makeAsyncIterator()
            var selectedPort: NWEndpoint.Port?
            for _ in 0..<(mode == "idle-then-edit" ? 6 : 1) {
                guard let port = await iterator.next() else { throw GateError.failed("listener did not start") }
                selectedPort = port
            }
            guard let port = selectedPort else { throw GateError.failed("missing port") }
            if mode == "idle-then-edit" {
                source.title = "Edited after five idle listener expirations"
                try await sender.save(source)
            }
            var snapshotCalls = 0
            let outgoing = PeerAutomaticSyncController(store: sender, route: .send(.hostPort(host: "127.0.0.1", port: port)),
                currentAuthorization: { sendAuth },
                makeProbe: { _ in PeerTLSProbe(pair: try .init(identity: b.identity,
                    scannedPeerSHA256: a.pin, peerCertificateDER: a.der, generation: generation)) },
                snapshot: { ids in
                    snapshotCalls += 1
                    if mode == "local-busy" && snapshotCalls == 1 { throw TextSnapshotError.busy }
                    return try await sender.exportTextSnapshot(ids: mode == "snapshot-outside-scope" ? [other.id] : ids)
                },
                receive: { _, _ in throw GateError.failed("sender must not receive") })
            outgoing.update(.init(enabled: true, foreground: true, protectedDataAvailable: true, authorization: sendAuth))
            for _ in 0..<1500 {
                if outgoing.status == .blocked { break }
                if outgoing.status == .waiting {
                    let received = try await receiver.list(includeArchived: true)
                    if !received.isEmpty { break }
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let received = try await receiver.list(includeArchived: true)
            let local = try await sender.list(includeArchived: true)
            let pending = try await sender.pendingTextRevisionSendIDs()
            let reused: Bool
            if let pendingID { reused = try await sender.textRevisionSend(id: pendingID)?.delivered == true }
            else { reused = true }
            let expectedSuccess = mode == "automatic-send" || mode == "pending-retry" || mode == "idle-then-edit" || mode == "local-busy"
            let passed = local.count == 2 && (mode != "idle-then-edit" || listenerCreations >= 6) &&
                (mode != "local-busy" || snapshotCalls >= 2) && (expectedSuccess
                ? outgoing.status == .waiting && received == [source] && pending.isEmpty && reused
                : outgoing.status == .blocked && received.isEmpty && pending.isEmpty)
            outgoing.stop()
            incoming.stop()
            ports.continuation.finish()
            let result = Result(name: mode, passed: passed, sourceCount: local.count,
                receivedCount: received.count, reusedPendingTransfer: reused)
            results.append(result)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: output, options: .atomic)
            print("automatic \(mode): \(passed ? "PASS" : "FAIL")")
        }
        let handshakeFailure = try await acceptedButIncomplete(a: a, b: b)
        results.append(.init(name: "accepted-incomplete-is-failure", passed: handshakeFailure,
            sourceCount: 0, receivedCount: 0, reusedPendingTransfer: true))
        let finalEncoder = JSONEncoder(); finalEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try finalEncoder.encode(results).write(to: output, options: .atomic)
        guard results.allSatisfy(\.passed) else { throw GateError.failed("Automatic sync adapter failed") }
    }
    /// A TCP peer that never starts TLS must consume a failure, not receive the
    /// ordinary no-connection idle exemption.
    private static func acceptedButIncomplete(a: FixtureIdentity, b: FixtureIdentity) async throws -> Bool {
        let probe = PeerTLSProbe(pair: try .init(identity: a.identity,
            scannedPeerSHA256: b.pin, peerCertificateDER: b.der, generation: UUID()),
            timeoutSeconds: 2)
        let raw = IncompletePeerConnection()
        let events = AsyncStream<Bool>.makeStream()
        defer { probe.cancel(); raw.cancel(); events.continuation.finish() }
        probe.listenForTransfer(on: .any, ready: { raw.connect($0) }, completion: { result in
            if case .failure(let error) = result,
               let failure = error as? PeerTLSProbe.Failure, case .timeout = failure {
                events.continuation.yield(true)
            } else {
                if case .success(let channel) = result { channel.cancel() }
                events.continuation.yield(false)
            }
        })
        var iterator = events.stream.makeAsyncIterator()
        return await iterator.next() == true
    }

}


private final class IncompletePeerConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?
    func connect(_ port: NWEndpoint.Port) {
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        lock.lock(); self.connection = connection; lock.unlock()
        connection.start(queue: DispatchQueue(label: "Orivyn.IncompletePeerFixture"))
    }
    func cancel() {
        lock.lock(); let connection = self.connection; self.connection = nil; lock.unlock()
        connection?.cancel()
    }
}
