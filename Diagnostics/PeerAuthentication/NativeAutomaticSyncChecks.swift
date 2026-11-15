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
        for mode in ["automatic-send", "pending-retry", "snapshot-outside-scope", "revoked-sender"] {
            let directory = root.appendingPathComponent("automatic-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sender = try SQLiteConversationStore(url: directory.appendingPathComponent("sender.sqlite"))
            let receiver = try SQLiteConversationStore(url: directory.appendingPathComponent("receiver.sqlite"))
            let source = Conversation(title: "Synthetic automatic exchange")
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
            let incoming = PeerAutomaticSyncController(store: receiver, route: .receive(.any),
                currentAuthorization: { receiveAuth },
                makeProbe: { _ in PeerTLSProbe(pair: try .init(identity: a.identity,
                    scannedPeerSHA256: b.pin, peerCertificateDER: b.der, generation: generation)) },
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
            guard let port = await iterator.next() else { throw GateError.failed("listener did not start") }
            let outgoing = PeerAutomaticSyncController(store: sender, route: .send(.hostPort(host: "127.0.0.1", port: port)),
                currentAuthorization: { sendAuth },
                makeProbe: { _ in PeerTLSProbe(pair: try .init(identity: b.identity,
                    scannedPeerSHA256: a.pin, peerCertificateDER: a.der, generation: generation)) },
                snapshot: { ids in try await sender.exportTextSnapshot(ids: mode == "snapshot-outside-scope" ? [other.id] : ids) },
                receive: { _, _ in throw GateError.failed("sender must not receive") })
            outgoing.update(.init(enabled: true, foreground: true, protectedDataAvailable: true, authorization: sendAuth))
            for _ in 0..<1500 {
                if outgoing.status == .waiting || outgoing.status == .blocked { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let received = try await receiver.list(includeArchived: true)
            let local = try await sender.list(includeArchived: true)
            let pending = try await sender.pendingTextRevisionSendIDs()
            let reused: Bool
            if let pendingID { reused = try await sender.textRevisionSend(id: pendingID)?.delivered == true }
            else { reused = true }
            let expectedSuccess = mode == "automatic-send" || mode == "pending-retry"
            let passed = local.count == 2 && (expectedSuccess
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
        guard results.allSatisfy(\.passed) else { throw GateError.failed("Automatic sync adapter failed") }
    }
}
