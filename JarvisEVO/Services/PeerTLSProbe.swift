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
        self.identity = identity; self.peerCertificate = certificate
        self.peerPin = scannedPeerSHA256; self.generation = generation
    }
}

/// A genuine Network.framework mutual-TLS control probe, not an authorization
/// token for data transfer. It can exchange only OS-random challenges and echoes,
/// closes after success, and cannot invoke persistence or send conversation bytes.
/// All mutable state and Security/Network callbacks use this one private queue.
final class PeerTLSProbe: @unchecked Sendable {
    enum Failure: Error { case invalidPair, invalidIdentity, randomFailure, invalidPeer, invalidControl, timeout, canceled, alreadyStarted }
    struct Result: Sendable {
        let pairingGeneration: UUID
        let peerCertificateSHA256: Data
        let localNonce: Data
        let peerNonce: Data
    }
    private let queue = DispatchQueue(label: "Orivyn.PeerTLSProbe")
    private let pair: PeerTLSProbePair
    private var connection: NWConnection?
    private var listener: NWListener?
    private var started = false
    private var active = false
    private var exchangedChallenge = false
    private var localNonce = Data()
    private var completion: (@Sendable (Swift.Result<Result, Error>) -> Void)?

    init(pair: PeerTLSProbePair) { self.pair = pair }

    /// Caller must explicitly select a paired endpoint. No discovery or auto-start.
    func connect(to endpoint: NWEndpoint, completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void) {
        queue.async {
            do {
                guard try self.begin(completion) else { return }
                let connection = NWConnection(to: endpoint, using: try self.parameters(peerIsServer: true))
                self.attach(connection)
            } catch { self.finish(.failure(error)) }
        }
    }

    /// Listener creation requires the explicit locally verified pair above. The
    /// caller must retain the probe and cancel on lock/background/pair revocation.
    func listen(on port: NWEndpoint.Port, ready: @escaping @Sendable (NWEndpoint.Port) -> Void,
                completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void) {
        queue.async {
            do {
                guard try self.begin(completion) else { return }
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

    func cancel() { queue.async { self.finish(.failure(Failure.canceled)) } }

    private func begin(_ completion: @escaping @Sendable (Swift.Result<Result, Error>) -> Void) throws -> Bool {
        guard !started else { completion(.failure(Failure.alreadyStarted)); return false }
        started = true; active = true; self.completion = completion
        localNonce = Data(count: 32)
        let status = localNonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Failure.randomFailure }
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.active else { return }
            self.finish(.failure(Failure.timeout))
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
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        let callback = completion; completion = nil; localNonce = Data()
        callback?(result)
    }
}
#endif
