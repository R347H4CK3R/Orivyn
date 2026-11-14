import XCTest
@testable import JarvisEVO

final class PeerSyncControlFrameTests: XCTestCase {
    func testChallengeAndEchoRoundTrip() throws {
        let id = UUID(), nonce = Data(repeating: 1, count: 32), peer = Data(repeating: 2, count: 32)
        for frame in [PeerSyncControlFrame.challenge(pairingGeneration: id, nonce: nonce), .echo(pairingGeneration: id, senderNonce: nonce, receiverNonce: peer)] {
            XCTAssertEqual(try PeerSyncControlFrame.decode(frame.encoded()), frame)
        }
    }
    func testEveryFragmentationBoundary() throws {
        let frame = PeerSyncControlFrame.echo(pairingGeneration: UUID(), senderNonce: Data(repeating: 1, count: 32), receiverNonce: Data(repeating: 2, count: 32))
        let data = try frame.encoded()
        for split in 0..<data.count {
            var accumulator = PeerSyncControlFrameAccumulator()
            XCTAssertNil(try accumulator.append(Data(data.prefix(split))))
            XCTAssertEqual(try accumulator.append(Data(data.dropFirst(split))), frame)
        }
    }
    func testOneByteFragmentsAndNoSecondFrame() throws {
        let frame = PeerSyncControlFrame.challenge(pairingGeneration: UUID(), nonce: Data(repeating: 1, count: 32))
        let data = try frame.encoded()
        var accumulator = PeerSyncControlFrameAccumulator()
        for byte in data.dropLast() { XCTAssertNil(try accumulator.append(Data([byte]))) }
        XCTAssertEqual(try accumulator.append(Data([data.last!])), frame)
        XCTAssertThrowsError(try accumulator.append(Data()))
    }
    func testRejectsOversizedOrWrongDeclaredLengthBeforeBody() throws {
        for length: UInt32 in [0, 1, 67, 69, 100, 101, UInt32.max] {
            let header = Data([0x4f, 0x52, 0x56, 1, 1, UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
            XCTAssertThrowsError(try PeerSyncControlFrame.bodyLength(header: header))
            var accumulator = PeerSyncControlFrameAccumulator()
            XCTAssertThrowsError(try accumulator.append(header))
        }
    }
    func testWrongMagicVersionAndUnknownKindReject() throws {
        let data = try PeerSyncControlFrame.challenge(pairingGeneration: UUID(), nonce: Data(repeating: 1, count: 32)).encoded()
        for position in 0..<5 {
            var invalid = data; invalid[position] = 255
            XCTAssertThrowsError(try PeerSyncControlFrame.decode(invalid))
        }
    }
    func testTruncationAndTrailingBytesReject() throws {
        let data = try PeerSyncControlFrame.challenge(pairingGeneration: UUID(), nonce: Data(repeating: 1, count: 32)).encoded()
        for length in 0..<data.count { XCTAssertThrowsError(try PeerSyncControlFrame.decode(Data(data.prefix(length)))) }
        XCTAssertThrowsError(try PeerSyncControlFrame.decode(data + Data([0])))
        var accumulator = PeerSyncControlFrameAccumulator()
        XCTAssertThrowsError(try accumulator.append(data + data))
    }
    func testNonCanonicalAndMalformedIdentityReject() throws {
        var data = try PeerSyncControlFrame.challenge(pairingGeneration: UUID(), nonce: Data(repeating: 1, count: 32)).encoded()
        data.replaceSubrange(9..<45, with: Data("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa".utf8))
        XCTAssertThrowsError(try PeerSyncControlFrame.decode(data))
        data[9] = 255
        XCTAssertThrowsError(try PeerSyncControlFrame.decode(data))
    }
    func testOnlyFullLengthRandomChallengesCanBeEncoded() throws {
        for length in [0, 1, 31, 33, 100] {
            XCTAssertThrowsError(try PeerSyncControlFrame.challenge(pairingGeneration: UUID(), nonce: Data(repeating: 0, count: length)).encoded())
            XCTAssertThrowsError(try PeerSyncControlFrame.echo(pairingGeneration: UUID(), senderNonce: Data(repeating: 0, count: 32), receiverNonce: Data(repeating: 0, count: length)).encoded())
        }
    }
}
