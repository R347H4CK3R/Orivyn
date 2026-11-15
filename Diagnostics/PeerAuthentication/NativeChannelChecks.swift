import Foundation
import CryptoKit

/// Real Network.framework channels only; no database or app enablement.
final class ChannelEvents: @unchecked Sendable {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private let expected: Set<String>
    private var values: [String: Bool] = [:]
    private var duplicate = false
    private var channels: [PeerTLSProbe.AuthenticatedChannel] = []
    init(_ keys: [String]) { expected = Set(keys); for _ in expected { group.enter() } }
    func retain(_ channel: PeerTLSProbe.AuthenticatedChannel) { lock.lock(); channels.append(channel); lock.unlock() }
    func record(_ key: String, _ passed: Bool) {
        lock.lock()
        guard expected.contains(key), values[key] == nil else { duplicate = true; lock.unlock(); return }
        values[key] = passed; lock.unlock(); group.leave()
    }
    func wait() -> Bool { group.wait(timeout: .now() + 45) == .success }
    func snapshot() -> (values: [String: Bool], duplicate: Bool) {
        lock.lock(); defer { lock.unlock() }; return (values, duplicate)
    }
    func close() {
        lock.lock(); let owned = channels; channels = []; lock.unlock()
        for channel in owned { channel.cancel() }
    }
}
struct ChannelGateResult: Codable {
    let name: String
    let passed: Bool
    let timedOut: Bool
    let duplicateCallbacks: Bool
    let events: [String: Bool]
}
@available(macOS 15.0, *)
enum NativeChannelChecks {
    static func transfer(_ name: String, a: FixtureIdentity, b: FixtureIdentity, payload: Data) throws -> ChannelGateResult {
        let generation = UUID(), aPin = a.pin, bPin = b.pin
        let server = PeerTLSProbe(pair: try .init(identity: a.identity, scannedPeerSHA256: bPin, peerCertificateDER: b.der, generation: generation))
        let client = PeerTLSProbe(pair: try .init(identity: b.identity, scannedPeerSHA256: aPin, peerCertificateDER: a.der, generation: generation))
        let expectedReceipt = Data(SHA256.hash(data: payload))
        let events = ChannelEvents(["serverBinding", "clientBinding", "requestSent", "requestReceived", "receiptSent", "receiptReceived"])
        server.listenForTransfer(on: .any, ready: { port in
            client.connectForTransfer(to: .hostPort(host: "127.0.0.1", port: port)) { result in
                switch result {
                case .failure:
                    events.record("clientBinding", false); events.record("requestSent", false); events.record("receiptReceived", false)
                case .success(let channel):
                    events.retain(channel)
                    events.record("clientBinding", channel.localCertificateSHA256 == bPin && channel.peerCertificateSHA256 == aPin && channel.pairingGeneration == generation)
                    channel.receive { result in
                        if case .success(let bytes) = result { events.record("receiptReceived", bytes == expectedReceipt) }
                        else { events.record("receiptReceived", false) }
                    }
                    channel.send(payload) { result in
                        if case .success = result { events.record("requestSent", true) }
                        else { events.record("requestSent", false) }
                    }
                }
            }
        }, completion: { result in
            switch result {
            case .failure:
                events.record("serverBinding", false); events.record("requestReceived", false); events.record("receiptSent", false)
            case .success(let channel):
                events.retain(channel)
                events.record("serverBinding", channel.localCertificateSHA256 == aPin && channel.peerCertificateSHA256 == bPin && channel.pairingGeneration == generation)
                channel.receive { result in
                    guard case .success(let received) = result else {
                        events.record("requestReceived", false); events.record("receiptSent", false); return
                    }
                    events.record("requestReceived", received == payload)
                    channel.send(Data(SHA256.hash(data: received))) { result in
                        if case .success = result { events.record("receiptSent", true) }
                        else { events.record("receiptSent", false) }
                    }
                }
            }
        })
        let finished = events.wait(), snapshot = events.snapshot()
        events.close(); server.cancel(); client.cancel()
        return .init(name: name, passed: finished && !snapshot.duplicate && snapshot.values.values.allSatisfy { $0 }, timedOut: !finished, duplicateCallbacks: snapshot.duplicate, events: snapshot.values)
    }
    static func rejectedSend(_ name: String, a: FixtureIdentity, b: FixtureIdentity, payload: Data, cancelFirst: Bool = false) throws -> ChannelGateResult {
        let generation = UUID(), aPin = a.pin, bPin = b.pin
        let server = PeerTLSProbe(pair: try .init(identity: a.identity, scannedPeerSHA256: bPin, peerCertificateDER: b.der, generation: generation))
        let client = PeerTLSProbe(pair: try .init(identity: b.identity, scannedPeerSHA256: aPin, peerCertificateDER: a.der, generation: generation))
        let events = ChannelEvents(["serverAuthenticated", "clientAuthenticated", "sendRejected", "receiveRejected"])
        server.listenForTransfer(on: .any, ready: { port in
            client.connectForTransfer(to: .hostPort(host: "127.0.0.1", port: port)) { result in
                guard case .success(let channel) = result else {
                    events.record("clientAuthenticated", false); events.record("sendRejected", false); return
                }
                events.retain(channel); events.record("clientAuthenticated", true)
                if cancelFirst { channel.cancel() }
                channel.send(payload) { result in
                    if case .failure = result { events.record("sendRejected", true) }
                    else { events.record("sendRejected", false) }
                }
            }
        }, completion: { result in
            guard case .success(let channel) = result else {
                events.record("serverAuthenticated", false); events.record("receiveRejected", false); return
            }
            events.retain(channel); events.record("serverAuthenticated", true)
            channel.receive { result in
                if case .failure = result { events.record("receiveRejected", true) }
                else { events.record("receiveRejected", false) }
            }
        })
        let finished = events.wait(), snapshot = events.snapshot()
        events.close(); server.cancel(); client.cancel()
        return .init(name: name, passed: finished && !snapshot.duplicate && snapshot.values.values.allSatisfy { $0 }, timedOut: !finished, duplicateCallbacks: snapshot.duplicate, events: snapshot.values)
    }
    static func unpaired(a: FixtureIdentity, b: FixtureIdentity, c: FixtureIdentity) throws -> ChannelGateResult {
        let generation = UUID()
        let server = PeerTLSProbe(pair: try .init(identity: a.identity, scannedPeerSHA256: b.pin, peerCertificateDER: b.der, generation: generation))
        let client = PeerTLSProbe(pair: try .init(identity: c.identity, scannedPeerSHA256: a.pin, peerCertificateDER: a.der, generation: generation))
        let events = ChannelEvents(["serverDenied", "clientDenied"])
        server.listenForTransfer(on: .any, ready: { port in
            client.connectForTransfer(to: .hostPort(host: "127.0.0.1", port: port)) { result in
                if case .failure = result { events.record("clientDenied", true) }
                else { events.record("clientDenied", false) }
            }
        }, completion: { result in
            if case .failure = result { events.record("serverDenied", true) }
            else { events.record("serverDenied", false) }
        })
        let finished = events.wait(), snapshot = events.snapshot()
        events.close(); server.cancel(); client.cancel()
        return .init(name: "unpaired-no-channel", passed: finished && !snapshot.duplicate && snapshot.values.values.allSatisfy { $0 }, timedOut: !finished, duplicateCallbacks: snapshot.duplicate, events: snapshot.values)
    }
    static func run(root: URL, password: String, output: URL) throws {
        let a = try FixtureIdentity(root: root, name: "a", password: password)
        let b = try FixtureIdentity(root: root, name: "b", password: password)
        let c = try FixtureIdentity(root: root, name: "c", password: password)
        var results: [ChannelGateResult] = []
        func record(_ result: ChannelGateResult) throws {
            results.append(result)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: output, options: .atomic)
            print("\(result.name): \(result.passed ? "PASS" : "FAIL")")
        }
        try record(transfer("authenticated-request-receipt", a: a, b: b, payload: Data("synthetic revision fixture".utf8)))
        try record(transfer("fragmented-request-receipt", a: a, b: b, payload: Data((0..<262177).map { UInt8($0 % 251) })))
        try record(transfer("maximum-request-receipt", a: a, b: b, payload: Data(repeating: 0x5a, count: 5_001_024)))
        try record(rejectedSend("empty-payload-denied", a: a, b: b, payload: Data()))
        try record(rejectedSend("oversized-payload-denied", a: a, b: b, payload: Data(repeating: 0, count: 5_001_025)))
        try record(rejectedSend("canceled-channel-denied", a: a, b: b, payload: Data("do not send".utf8), cancelFirst: true))
        try record(unpaired(a: a, b: b, c: c))
        guard results.allSatisfy(\.passed) else { throw GateError.failed("Authenticated channel gate failed") }
    }
}
