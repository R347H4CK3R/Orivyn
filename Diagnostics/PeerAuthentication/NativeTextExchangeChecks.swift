import Foundation
import CryptoKit
import Network

private final class NativeChannelPairBox: @unchecked Sendable {
    private let lock = NSLock(), group = DispatchGroup()
    private var values: [String: PeerTLSProbe.AuthenticatedChannel] = [:]
    private var failed = false
    init() { group.enter(); group.enter() }
    func put(_ key: String, _ result: Result<PeerTLSProbe.AuthenticatedChannel, Error>) {
        lock.lock()
        switch result { case .success(let channel): values[key] = channel; case .failure: failed = true }
        lock.unlock(); group.leave()
    }
    func take() throws -> (PeerTLSProbe.AuthenticatedChannel, PeerTLSProbe.AuthenticatedChannel) {
        guard group.wait(timeout: .now() + 40) == .success else { throw GateError.failed("Channel pair deadline") }
        lock.lock(); defer { lock.unlock() }
        guard !failed, let server = values["server"], let client = values["client"] else { throw GateError.failed("Channel pair authentication") }
        return (server, client)
    }
}
private struct NativeExchangePair {
    let server: PeerTLSProbe, client: PeerTLSProbe
    let incoming: PeerTLSProbe.AuthenticatedChannel, outgoing: PeerTLSProbe.AuthenticatedChannel
    func close() { incoming.cancel(); outgoing.cancel(); server.cancel(); client.cancel() }
}
struct NativeTextExchangeResult: Codable {
    let name: String, passed: Bool, receiverUnchanged: Bool, senderDelivered: Bool
}
@available(macOS 15.0, *)
enum NativeTextExchangeChecks {
    private static func pair(a: FixtureIdentity, b: FixtureIdentity, generation: UUID) throws -> NativeExchangePair {
        let server = PeerTLSProbe(pair: try .init(identity: a.identity, scannedPeerSHA256: b.pin, peerCertificateDER: b.der, generation: generation))
        let client = PeerTLSProbe(pair: try .init(identity: b.identity, scannedPeerSHA256: a.pin, peerCertificateDER: a.der, generation: generation))
        let box = NativeChannelPairBox()
        server.listenForTransfer(on: .any, ready: { port in
            client.connectForTransfer(to: .hostPort(host: "127.0.0.1", port: port)) { box.put("client", $0) }
        }, completion: { box.put("server", $0) })
        do { let (incoming, outgoing) = try box.take(); return .init(server: server, client: client, incoming: incoming, outgoing: outgoing) }
        catch { server.cancel(); client.cancel(); throw error }
    }
    private static func outcome(_ operation: @Sendable () async throws -> TextRevisionReceiveSummary) async -> Result<TextRevisionReceiveSummary, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    private static func rawSend(_ data: Data, channel: PeerTLSProbe.AuthenticatedChannel) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.send(data) { continuation.resume(with: $0) }
        }
    }
    private static func rawReceive(_ channel: PeerTLSProbe.AuthenticatedChannel) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in channel.receive { continuation.resume(with: $0) } }
    }
    private static func check(_ mode: String, a: FixtureIdentity, b: FixtureIdentity, root: URL) async throws -> NativeTextExchangeResult {
        let directory = root.appendingPathComponent("db-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sender = try SQLiteConversationStore(url: directory.appendingPathComponent("sender.sqlite"))
        let receiver = try SQLiteConversationStore(url: directory.appendingPathComponent("receiver.sqlite"))
        let generation = UUID(), epoch = try await receiver.textReceiveEpoch()
        let source = Conversation(id: UUID(), title: "Synthetic peer exchange", createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0), isArchived: false,
            messages: [ChatMessage(role: .user, content: "EXCHANGE-" + UUID().uuidString)])
        try await sender.save(source)
        let snapshot = try await sender.exportTextSnapshot(ids: [source.id])
        let staged = try await sender.stageTextRevisionSend(snapshot, senderCertificateSHA256: b.pin,
            peerCertificateSHA256: a.pin, pairingGeneration: generation, receiverEpoch: mode == "wrong-epoch" ? UUID() : epoch)
        if mode == "revoked-receiver" { try await receiver.revokeTextPeer(peerCertificateSHA256: b.pin, pairingGeneration: generation) }
        let channels = try pair(a: a, b: b, generation: generation)
        defer { channels.close() }
        let approved: Set<UUID> = mode == "unapproved-source" ? [UUID()] : [source.id]
        let outgoing = channels.outgoing, incoming = channels.incoming
        async let received = outcome {
            if mode == "false-receipt-digest" || mode == "false-receipt-transfer" {
                defer { incoming.cancel() }
                let request = try UnverifiedTextRevisionPacket.decode(await rawReceive(incoming))
                let summary = TextRevisionReceiveSummary(records: [.init(sourceID: source.id, localID: source.id, disposition: .inserted, preservedLocalID: nil)])
                let id = request.identity
                let identity = TextSendIdentity(receiverEpoch: id.receiverEpoch, transfer: mode == "false-receipt-transfer" ? UUID() : id.transfer,
                    senderCertificateSHA256: id.senderCertificateSHA256, receiverCertificateSHA256: id.receiverCertificateSHA256, pairingGeneration: id.pairingGeneration)
                let receipt = try UnverifiedTextRevisionPacket.receipt(identity: identity,
                    requestSHA256: mode == "false-receipt-digest" ? Data(repeating: 0, count: 32) : request.declaredSHA256, summary: summary)
                try await rawSend(receipt.data, channel: incoming)
                return summary
            }
            return try await PeerTextRevisionExchange.receive(approvedSourceIDs: approved, expectedEpoch: epoch, store: receiver, over: incoming)
        }
        async let sent = outcome {
            if mode == "wrong-request-digest" {
                defer { outgoing.cancel() }
                let request = try UnverifiedTextRevisionPacket.request(identity: staged.identity, payload: staged.payload, declaredSHA256: Data(repeating: 0, count: 32))
                try await rawSend(request.data, channel: outgoing)
                return try UnverifiedTextRevisionPacket.decode(await rawReceive(outgoing)).receiptSummary()
            }
            return try await PeerTextRevisionExchange.send(transferID: staged.identity.transfer, store: sender, over: outgoing)
        }
        let (receiveResult, sendResult) = await (received, sent)
        let stored = try await receiver.list(includeArchived: true)
        let delivered = try await sender.textRevisionSend(id: staged.identity.transfer)?.delivered == true
        let passed: Bool
        if mode == "approved-request-receipt" {
            if case .success(let a) = receiveResult, case .success(let b) = sendResult {
                passed = a == b && stored == [source] && delivered
            } else { passed = false }
        } else if mode.hasPrefix("false-receipt") {
            if case .failure = sendResult { passed = stored.isEmpty && !delivered } else { passed = false }
        } else {
            if case .failure = receiveResult, case .failure = sendResult { passed = stored.isEmpty && !delivered }
            else { passed = false }
        }
        return .init(name: mode, passed: passed, receiverUnchanged: stored.isEmpty, senderDelivered: delivered)
    }
    static func run(root: URL, password: String, output: URL) async throws {
        let a = try FixtureIdentity(root: root, name: "a", password: password)
        let b = try FixtureIdentity(root: root, name: "b", password: password)
        var rows: [NativeTextExchangeResult] = []
        for mode in ["approved-request-receipt", "unapproved-source", "wrong-epoch", "revoked-receiver", "wrong-request-digest", "false-receipt-digest", "false-receipt-transfer"] {
            let result = try await check(mode, a: a, b: b, root: root); rows.append(result)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rows).write(to: output, options: .atomic)
            print("text-exchange \(mode): \(result.passed ? "PASS" : "FAIL")")
        }
        guard rows.allSatisfy(\.passed) else { throw GateError.failed("Live text exchange failed") }
    }
}
