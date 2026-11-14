import Foundation

/// Content-free control protocol for the gated native TLS probe. No message kind
/// carries conversations, attachment metadata, credentials or arbitrary payloads.
enum PeerSyncControlFrame: Equatable, Sendable {
    case challenge(pairingGeneration: UUID, nonce: Data)
    case echo(pairingGeneration: UUID, senderNonce: Data, receiverNonce: Data)

    static let headerBytes = 9
    static let maximumBodyBytes = 100
    enum Failure: Error { case invalidHeader, invalidLength, invalidBody, incomplete, trailingBytes }

    func encoded() throws -> Data {
        let kind: UInt8
        var body = Data()
        switch self {
        case let .challenge(generation, nonce):
            guard nonce.count == 32 else { throw Failure.invalidBody }
            kind = 1; body.append(contentsOf: generation.uuidString.utf8); body.append(nonce)
        case let .echo(generation, sender, receiver):
            guard sender.count == 32, receiver.count == 32 else { throw Failure.invalidBody }
            kind = 2; body.append(contentsOf: generation.uuidString.utf8); body.append(sender); body.append(receiver)
        }
        let length = UInt32(body.count)
        var result = Data([0x4f, 0x52, 0x56, 0x01, kind,
                           UInt8((length >> 24) & 255), UInt8((length >> 16) & 255),
                           UInt8((length >> 8) & 255), UInt8(length & 255)])
        result.append(body)
        return result
    }

    /// Validate before allocating or scheduling the declared body read.
    static func bodyLength(header: Data) throws -> Int {
        let bytes = [UInt8](header)
        guard bytes.count == headerBytes, Array(bytes.prefix(4)) == [0x4f, 0x52, 0x56, 0x01],
              bytes[4] == 1 || bytes[4] == 2 else { throw Failure.invalidHeader }
        let length = bytes[5...8].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let expected: UInt32 = bytes[4] == 1 ? 68 : 100
        guard length == expected, length <= maximumBodyBytes else { throw Failure.invalidLength }
        return Int(length)
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count >= headerBytes else { throw Failure.incomplete }
        let length = try bodyLength(header: Data(data.prefix(headerBytes)))
        guard data.count >= headerBytes + length else { throw Failure.incomplete }
        guard data.count == headerBytes + length else { throw Failure.trailingBytes }
        let bytes = [UInt8](data)
        guard let text = String(bytes: bytes[9..<45], encoding: .utf8),
              let generation = UUID(uuidString: text), text == generation.uuidString else { throw Failure.invalidBody }
        let nonce = Data(bytes[45..<77])
        if bytes[4] == 1 { return .challenge(pairingGeneration: generation, nonce: nonce) }
        return .echo(pairingGeneration: generation, senderNonce: nonce, receiverNonce: Data(bytes[77..<109]))
    }
}

/// Exactly one bounded frame. A transport must explicitly request the next frame;
/// concatenated unsolicited frames fail instead of being buffered indefinitely.
struct PeerSyncControlFrameAccumulator {
    private var bytes = Data()
    private var finished = false
    mutating func append(_ fragment: Data) throws -> PeerSyncControlFrame? {
        guard !finished else { throw PeerSyncControlFrame.Failure.trailingBytes }
        guard fragment.count <= PeerSyncControlFrame.headerBytes + PeerSyncControlFrame.maximumBodyBytes - bytes.count else {
            throw PeerSyncControlFrame.Failure.invalidLength
        }
        bytes.append(fragment)
        guard bytes.count >= PeerSyncControlFrame.headerBytes else { return nil }
        let length = try PeerSyncControlFrame.bodyLength(header: Data(bytes.prefix(PeerSyncControlFrame.headerBytes)))
        guard bytes.count >= PeerSyncControlFrame.headerBytes + length else { return nil }
        let frame = try PeerSyncControlFrame.decode(bytes)
        finished = true
        return frame
    }
}
