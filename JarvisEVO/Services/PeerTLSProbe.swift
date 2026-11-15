// Deliberately absent from production compilation until an Apple SDK/device gate
// validates this spike. No build configuration in this repository enables it.
#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit)
import Foundation
@preconcurrency import Network
@preconcurrency import Security
import CryptoKit
#if canImport(X509) && canImport(SwiftASN1)
import X509
import SwiftASN1
#endif

/// Explicit locally supplied pairing material. This is not populated from a peer's
/// network message. The eventual pairing UI must independently verify the DER pin.
struct PeerTLSProbePair {
    fileprivate let identity: SecIdentity
    fileprivate let peerCertificate: SecCertificate
    fileprivate let localPin: Data
    fileprivate let peerPin: Data
    fileprivate let generation: UUID

    init(identity: SecIdentity, scannedPeerSHA256: Data, peerCertificateDER: Data, generation: UUID) throws {
        guard scannedPeerSHA256.count == 32,
              peerCertificateDER.count <= 16_384,
              Data(SHA256.hash(data: peerCertificateDER)) == scannedPeerSHA256,
              let certificate = SecCertificateCreateWithData(nil, peerCertificateDER as CFData) else {
            throw PeerTLSProbe.Failure.invalidPair
        }
        var local: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &local) == errSecSuccess,
              let local, SecCertificateCopyData(local) as Data != peerCertificateDER else {
            throw PeerTLSProbe.Failure.invalidPair
        }
        self.localPin = Data(SHA256.hash(data: SecCertificateCopyData(local) as Data))
        self.identity = identity; self.peerCertificate = certificate
        self.peerPin = scannedPeerSHA256; self.generation = generation
    }
}

/// Experimental mutual-TLS authentication and one-shot bounded transport.
/// Probe results are not transfer authority. Only the transfer API retains the
/// same authenticated connection; no API here authorizes database mutations.
/// All mutable state and Security/Network callbacks use this one private queue.
final class PeerTLSProbe: @unchecked Sendable {
    enum Failure: Error { case invalidPair, invalidIdentity, randomFailure, invalidPeer, invalidControl, timeout, idleTimeout, canceled, alreadyStarted, invalidPayload }
    struct Result: Sendable {
        let pairingGeneration: UUID
        let peerCertificateSHA256: Data
        let localNonce: Data
        let peerNonce: Data
    }
    private let queue = DispatchQueue(label: "Orivyn.PeerTLSProbe")
    private let pair: PeerTLSProbePair
    private let timeoutSeconds: TimeInterval
    private var connection: NWConnection?
    private var listener: NWListener?
    private var started = false
    private var active = false
    private var exchangedChallenge = false
    private var localNonce = Data()
    private var completion: (@Sendable (Swift.Result<Result, Error>) -> Void)?

    private var transferCompletion: (@Sendable (Swift.Result<AuthenticatedChannel, Error>) -> Void)?
    private weak var transferredChannel: AuthenticatedChannel?

    /// A shorter deadline supports diagnostics; callers cannot extend the
    /// production 30-second bound. Non-finite values use the production default.
    init(pair: PeerTLSProbePair, timeoutSeconds: TimeInterval = 30) {
        self.pair = pair
        self.timeoutSeconds = timeoutSeconds.isFinite ? min(max(timeoutSeconds, 0.1), 30) : 30
    }

    /// Caller must explicitly select a paired endpoint. No discovery or auto-start.
    func connect(to endpoint: NWEndpoint, completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void) {
        connect(to: endpoint, completion: completion, transfer: nil)
    }

    func connectForTransfer(to endpoint: NWEndpoint, completion: @escaping @Sendable (Swift.Result<AuthenticatedChannel, Error>) -> Void) {
        connect(to: endpoint, completion: { _ in }, transfer: completion)
    }

    private func connect(to endpoint: NWEndpoint, completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void,
                         transfer: (@Sendable (Swift.Result<AuthenticatedChannel, Error>) -> Void)?) {
        queue.async {
            do {
                guard try self.begin(completion, transfer: transfer) else { return }
                let connection = NWConnection(to: endpoint, using: try self.parameters(peerIsServer: true))
                self.attach(connection)
            } catch { self.finish(.failure(error)) }
        }
    }

    /// Listener creation requires the explicit locally verified pair above. The
    /// caller must retain the probe and cancel on lock/background/pair revocation.
    func listen(on port: NWEndpoint.Port, ready: @escaping @Sendable (NWEndpoint.Port) -> Void,
                completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void) {
        listen(on: port, ready: ready, completion: completion, transfer: nil)
    }

    func listenForTransfer(on port: NWEndpoint.Port, ready: @escaping @Sendable (NWEndpoint.Port) -> Void,
                           completion: @escaping @Sendable (Swift.Result<AuthenticatedChannel, Error>) -> Void) {
        listen(on: port, ready: ready, completion: { _ in }, transfer: completion)
    }

    private func listen(on port: NWEndpoint.Port, ready: @escaping @Sendable (NWEndpoint.Port) -> Void,
                        completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void,
                        transfer: (@Sendable (Swift.Result<AuthenticatedChannel, Error>) -> Void)?) {
        queue.async {
            do {
                guard try self.begin(completion, transfer: transfer) else { return }
                let listener = try NWListener(using: self.parameters(peerIsServer: false), on: port)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self, self.active else { return }
                    switch state {
                    case .ready: if let port = self.listener?.port { ready(port) }
                    case .failed(let error): self.finish(.failure(error))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self, self.active, self.connection == nil else { connection.cancel(); return }
                    self.attach(connection)
                    // One paired connection only; no additional accepts.
                    self.listener?.cancel(); self.listener = nil
                }
                listener.start(queue: self.queue)
            } catch { self.finish(.failure(error)) }
        }
    }

    func cancel() { queue.async {
        self.transferredChannel?.cancel()
        self.finish(.failure(Failure.canceled))
    } }

    private func begin(_ completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void,
                       transfer: (@Sendable (Swift.Result<AuthenticatedChannel, Error>) -> Void)?) throws -> Bool {
        guard !started else {
            if let transfer { transfer(.failure(Failure.alreadyStarted)) }
            else { completion(.failure(Failure.alreadyStarted)) }
            return false
        }
        started = true; active = true; self.completion = completion; self.transferCompletion = transfer
        localNonce = Data(count: 32)
        let status = localNonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Failure.randomFailure }
        queue.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
            guard let self, self.active else { return }
            // Only a listener that accepted no connection is ordinary idle.
            // Accepted-but-incomplete TLS/challenge handshakes remain failures.
            let idle = self.listener != nil && self.connection == nil
            self.finish(.failure(idle ? Failure.idleTimeout : Failure.timeout))
        }
        return true
    }

    private func parameters(peerIsServer: Bool) throws -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        guard let identity = sec_identity_create(pair.identity) else { throw Failure.invalidIdentity }
        sec_protocol_options_set_local_identity(options, identity)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(options, true)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_false_start_enabled(options, false)
        sec_protocol_options_set_verify_block(options, { [weak self] _, suppliedTrust, complete in
            guard let self, self.active else { complete(false); return }
            let trust = sec_trust_copy_ref(suppliedTrust).takeRetainedValue()
            complete(self.validate(trust, peerIsServer: peerIsServer))
        }, queue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false
        return parameters
    }


    /// A pinned trust anchor is not necessarily checked for its self-signature or
    /// unknown critical extensions by platform trust. Use a maintained X.509
    /// implementation for those checks; missing validation support fails closed.
    private func validateCertificateProfile(_ leaf:SecCertificate,peerIsServer:Bool)->Bool {
        #if canImport(X509) && canImport(SwiftASN1)
        do {
            let parsed=try Certificate(leaf)
            let now=Date()
            guard parsed.issuer==parsed.subject,
                  parsed.notValidBefore<=now,now<=parsed.notValidAfter,
                  parsed.signatureAlgorithm == .ecdsaWithSHA256,
                  parsed.publicKey.isValidSignature(parsed.signature,for:parsed) else { return false }
            let understoodCritical:Set<ASN1ObjectIdentifier> = [[2,5,29,15],[2,5,29,19],[2,5,29,37],[2,5,29,17]]
            guard Set(parsed.extensions.map(\.oid)).count==parsed.extensions.count,
                  parsed.extensions.allSatisfy({ !$0.critical || understoodCritical.contains($0.oid) }),
                  try parsed.extensions.basicConstraints == .notCertificateAuthority,
                  let usage=try parsed.extensions.keyUsage,usage.digitalSignature,
                  !usage.keyCertSign,!usage.cRLSign,
                  let extended=try parsed.extensions.extendedKeyUsage,
                  extended.contains(peerIsServer ? .serverAuth : .clientAuth) else { return false }
            _=try parsed.extensions.subjectAlternativeNames
            return true
        } catch { return false }
        #else
        return false
        #endif
    }

    private func validate(_ trust: SecTrust, peerIsServer: Bool) -> Bool {
        guard active, SecTrustGetCertificateCount(trust) == 1,
              let leaf = SecTrustGetCertificateAtIndex(trust, 0),
              Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data)) == pair.peerPin,
              let key = SecCertificateCopyKey(leaf),
              let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              attributes[kSecAttrKeyType] as? String == kSecAttrKeyTypeECSECPrimeRandom as String,
              attributes[kSecAttrKeySizeInBits] as? Int == 256 else { return false }
        guard validateCertificateProfile(leaf,peerIsServer:peerIsServer) else { return false }
        // Pin the entire leaf and ask platform trust for the correct TLS usage,
        // using only the locally paired certificate as anchor and no network fetch.
        // The independent profile check above closes anchor exceptions. Platform
        // TLS policy validation remains required in addition to those checks.
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(peerIsServer, nil)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [pair.peerCertificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }

    private func attach(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.active else { return }
            switch state {
            case .ready:
                guard !self.exchangedChallenge else { return }
                self.exchangedChallenge = true
                self.exchangeChallenge()
            case .failed(let error): self.finish(.failure(error))
            case .cancelled: self.finish(.failure(Failure.canceled))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func exchangeChallenge() {
        send(.challenge(pairingGeneration: pair.generation, nonce: localNonce)) { [weak self] in
            self?.receive { [weak self] frame in
                guard let self, self.active,
                      case let .challenge(generation, remoteNonce) = frame,
                      generation == self.pair.generation, remoteNonce != self.localNonce else {
                    self?.finish(.failure(Failure.invalidControl)); return
                }
                self.send(.echo(pairingGeneration: generation, senderNonce: self.localNonce, receiverNonce: remoteNonce)) {
                    self.receive { frame in
                        guard self.active,
                              frame == .echo(pairingGeneration: generation, senderNonce: remoteNonce, receiverNonce: self.localNonce) else {
                            self.finish(.failure(Failure.invalidControl)); return
                        }
                        self.finish(.success(Result(pairingGeneration: generation, peerCertificateSHA256: self.pair.peerPin,
                                                    localNonce: self.localNonce, peerNonce: remoteNonce)))
                    }
                }
            }
        }
    }

    private func send(_ frame: PeerSyncControlFrame, then: @escaping @Sendable () -> Void) {
        guard active, let connection else { return }
        do {
            let bytes = try frame.encoded()
            connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                guard let self, self.active else { return }
                if let error { self.finish(.failure(error)) } else { then() }
            })
        } catch { finish(.failure(error)) }
    }

    private func receive(_ completion: @escaping @Sendable (PeerSyncControlFrame) -> Void) {
        readExactly(PeerSyncControlFrame.headerBytes) { [weak self] header in
            guard let self, self.active else { return }
            do {
                let count = try PeerSyncControlFrame.bodyLength(header: header)
                self.readExactly(count) { body in
                    do { completion(try PeerSyncControlFrame.decode(header + body)) }
                    catch { self.finish(.failure(error)) }
                }
            } catch { self.finish(.failure(error)) }
        }
    }

    private func readExactly(_ count: Int, completion: @escaping @Sendable (Data) -> Void) {
        guard active, let connection, count > 0, count <= PeerSyncControlFrame.maximumBodyBytes else { return }
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
            guard let self, self.active else { return }
            if let error { self.finish(.failure(error)); return }
            // EOF may accompany a complete final echo when the other peer closes.
            // Accept exactly requested bytes; a later required read rejects a short EOF.
            guard let data, data.count == count else { self.finish(.failure(Failure.invalidControl)); return }
            completion(data)
        }
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        guard active else { return }
        active = false
        let callback = completion, transfer = transferCompletion
        completion = nil; transferCompletion = nil; localNonce = Data()
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        let owned = connection; connection = nil
        owned?.stateUpdateHandler = nil
        if let transfer {
            switch result {
            case .success:
                guard let owned else { transfer(.failure(Failure.canceled)); return }
                let channel = AuthenticatedChannel(connection: owned, queue: queue, pair: pair)
                transferredChannel = channel
                transfer(.success(channel))
            case .failure(let error):
                owned?.cancel(); transfer(.failure(error))
            }
        } else {
            owned?.cancel(); callback?(result)
        }
    }

    /// One bounded message in each direction, bound to the exact TLS connection.
    /// The caller must retain this channel and cancel it on pair revocation,
    /// backgrounding or lock. It is not a durable lease or database capability.
    final class AuthenticatedChannel: @unchecked Sendable {
        let localCertificateSHA256: Data
        let peerCertificateSHA256: Data
        let pairingGeneration: UUID
        private let connection: NWConnection
        private let queue: DispatchQueue
        private static let magic = Data("ORIVDAT1".utf8)
        private static let maximumBytes = 5_001_024
        private static let chunkBytes = 65_536
        private var closed = false
        private var sendStarted = false
        private var receiveStarted = false
        private var sendCompletion: (@Sendable (Swift.Result<Void, Error>) -> Void)?
        private var receiveCompletion: (@Sendable (Swift.Result<Data, Error>) -> Void)?
        private var incoming = Data()
        private var outgoing = Data()

        fileprivate init(connection: NWConnection, queue: DispatchQueue, pair: PeerTLSProbePair) {
            self.connection = connection; self.queue = queue
            localCertificateSHA256 = pair.localPin
            peerCertificateSHA256 = pair.peerPin
            pairingGeneration = pair.generation
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .failed(let error): self.close(error)
                case .cancelled: self.close(Failure.canceled)
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 30) { [weak self] in self?.close(Failure.timeout) }
        }

        deinit { connection.cancel() }

        func cancel() { queue.async { self.close(Failure.canceled) } }

        func send(_ payload: Data, completion: @escaping @Sendable (Swift.Result<Void, Error>) -> Void) {
            queue.async {
                guard !self.closed else { completion(.failure(Failure.canceled)); return }
                guard !self.sendStarted else { completion(.failure(Failure.alreadyStarted)); return }
                self.sendStarted = true
                guard !payload.isEmpty, payload.count <= Self.maximumBytes else {
                    self.close(Failure.invalidPayload); completion(.failure(Failure.invalidPayload)); return
                }
                self.sendCompletion = completion
                var count = UInt32(payload.count).bigEndian
                self.outgoing = Self.magic
                withUnsafeBytes(of: &count) { self.outgoing.append(contentsOf: $0) }
                self.outgoing.append(payload)
                self.sendChunk(offset: 0)
            }
        }

        private func sendChunk(offset: Int) {
            guard !closed else { return }
            if offset == outgoing.count {
                outgoing = Data()
                let callback = sendCompletion; sendCompletion = nil
                callback?(.success(())); return
            }
            let end = min(offset + Self.chunkBytes, outgoing.count)
            let chunk = outgoing.subdata(in: offset..<end)
            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                guard let self, !self.closed else { return }
                if let error { self.close(error) } else { self.sendChunk(offset: end) }
            })
        }

        func receive(completion: @escaping @Sendable (Swift.Result<Data, Error>) -> Void) {
            queue.async {
                guard !self.closed else { completion(.failure(Failure.canceled)); return }
                guard !self.receiveStarted else { completion(.failure(Failure.alreadyStarted)); return }
                self.receiveStarted = true; self.receiveCompletion = completion
                self.readChunk(count: 12) { header in
                    guard header.prefix(8) == Self.magic else { self.close(Failure.invalidPayload); return }
                    let length = header.suffix(4).reduce(0) { ($0 << 8) | Int($1) }
                    guard length > 0, length <= Self.maximumBytes else { self.close(Failure.invalidPayload); return }
                    self.incoming.reserveCapacity(length)
                    self.readBody(remaining: length)
                }
            }
        }

        private func readBody(remaining: Int) {
            guard !closed else { return }
            guard remaining > 0 else {
                let bytes = incoming; incoming = Data()
                let callback = receiveCompletion; receiveCompletion = nil
                callback?(.success(bytes)); return
            }
            let count = min(remaining, Self.chunkBytes)
            readChunk(count: count) { bytes in
                self.incoming.append(bytes)
                self.readBody(remaining: remaining - bytes.count)
            }
        }

        private func readChunk(count: Int, completion: @escaping @Sendable (Data) -> Void) {
            guard !closed else { return }
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] bytes, _, _, error in
                guard let self, !self.closed else { return }
                if let error { self.close(error); return }
                guard let bytes, bytes.count == count else { self.close(Failure.invalidPayload); return }
                completion(bytes)
            }
        }

        private func close(_ error: Error) {
            guard !closed else { return }
            closed = true
            connection.stateUpdateHandler = nil; connection.cancel()
            incoming = Data(); outgoing = Data()
            let sent = sendCompletion, received = receiveCompletion
            sendCompletion = nil; receiveCompletion = nil
            sent?(.failure(error)); received?(.failure(error))
        }
    }
}
#endif
