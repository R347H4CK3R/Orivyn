import Foundation
import XCTest
@testable import JarvisEVO

final class TextRevisionPacketTests: XCTestCase {
    private func identity() -> TextSendIdentity {
        .init(receiverEpoch: UUID(), transfer: UUID(), senderCertificateSHA256: Data(repeating: 1, count: 32),
              receiverCertificateSHA256: Data(repeating: 2, count: 32), pairingGeneration: UUID())
    }
    private func payload() throws -> Data {
        let value = Conversation(id: UUID(), title: "Synthetic packet", createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0), isArchived: false,
            messages: [ChatMessage(role: .user, content: "Preserve local history")])
        return try TextRevisionEnvelope(records: [.init(base: nil, incoming: value)]).data
    }
    private func packet() throws -> UnverifiedTextRevisionPacket {
        try .request(identity: identity(), payload: payload(), declaredSHA256: Data(repeating: 3, count: 32))
    }
    private func replaceHeader(_ bytes: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        let size = bytes.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes.subdata(in: 4..<(4+size))) as? [String: Any])
        change(&object)
        let header = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var count = UInt32(header.count).bigEndian
        var result = withUnsafeBytes(of: &count) { Data($0) }; result.append(header); result.append(bytes.dropFirst(4+size))
        return result
    }
    func testRequestRoundTripRetainsExactBytesAndAllScopeFields() throws {
        let original = try packet(), decoded = try UnverifiedTextRevisionPacket.decode(original.data)
        XCTAssertEqual(decoded.identity, original.identity); XCTAssertEqual(decoded.payload, original.payload)
        XCTAssertEqual(decoded.declaredSHA256, original.declaredSHA256); XCTAssertEqual(decoded.kind, .request)
        XCTAssertEqual(decoded.data, original.data)
    }
    func testDecodeAcceptsNonZeroIndexedDataSlices() throws {
        let original = try packet()
        for padding in [1, 4, 1024] {
            let framed = Data(repeating: 0xff, count: padding) + original.data
            let slice = framed.dropFirst(padding)
            XCTAssertEqual(slice.startIndex, padding)
            let decoded = try UnverifiedTextRevisionPacket.decode(slice)
            XCTAssertEqual(decoded.data, original.data)
            XCTAssertEqual(decoded.identity, original.identity)
        }
    }

    func testSlicedReceiptAndBusyPacketsRetainValidation() throws {
        let id = identity(), digest = Data(repeating: 4, count: 32)
        let summary = TextRevisionReceiveSummary(records: [.init(sourceID: UUID(), localID: UUID(), disposition: .inserted, preservedLocalID: nil)])
        for original in [try UnverifiedTextRevisionPacket.receipt(identity: id, requestSHA256: digest, summary: summary),
                         try UnverifiedTextRevisionPacket.busy(identity: id, requestSHA256: digest)] {
            let slice = (Data(repeating: 0xff, count: 1024) + original.data).dropFirst(1024)
            let decoded = try UnverifiedTextRevisionPacket.decode(slice)
            XCTAssertEqual(decoded.data, original.data)
            XCTAssertEqual(decoded.kind, original.kind)
            XCTAssertEqual(decoded.identity, id)
            XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(slice.dropLast()))
        }
        let invalid = try replaceHeader(packet().data) { $0["payloadBytes"] = -1 }
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode((Data([0xff]) + invalid).dropFirst()))
    }

    func testReceiptRoundTripBindsExactRequestDigestAndSummary() throws {
        let id = identity()
        let summary = TextRevisionReceiveSummary(records: [.init(sourceID: UUID(), localID: UUID(), disposition: .inserted, preservedLocalID: nil)])
        let original = try UnverifiedTextRevisionPacket.receipt(identity: id, requestSHA256: Data(repeating: 4, count: 32), summary: summary)
        let decoded = try UnverifiedTextRevisionPacket.decode(original.data)
        XCTAssertEqual(decoded.kind, .receipt); XCTAssertEqual(decoded.identity, id)
        XCTAssertEqual(try decoded.receiptSummary(), summary)
        XCTAssertThrowsError(try packet().receiptSummary())
    }
    func testInvalidPinsDigestAndSamePeerAreRejected() throws {
        let id = identity(), body = try payload()
        let bad = TextSendIdentity(receiverEpoch: id.receiverEpoch, transfer: id.transfer,
            senderCertificateSHA256: Data(repeating: 1, count: 31), receiverCertificateSHA256: id.receiverCertificateSHA256, pairingGeneration: id.pairingGeneration)
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.request(identity: bad, payload: body, declaredSHA256: Data(repeating: 3, count: 32)))
        let same = TextSendIdentity(receiverEpoch: id.receiverEpoch, transfer: id.transfer,
            senderCertificateSHA256: id.senderCertificateSHA256, receiverCertificateSHA256: id.senderCertificateSHA256, pairingGeneration: id.pairingGeneration)
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.request(identity: same, payload: body, declaredSHA256: Data(repeating: 3, count: 32)))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.request(identity: id, payload: body, declaredSHA256: Data()))
    }
    func testTruncatedHeaderPayloadAndTrailingBytesAreRejected() throws {
        let bytes = try packet().data
        for size in [0, 1, 3, 4, bytes.count-1] { XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(Data(bytes.prefix(size)))) }
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(bytes + Data([0])))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(Data([255,255,255,255])))
    }
    func testUnknownHeaderFieldsAndVersionAreRejected() throws {
        let bytes = try packet().data
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(bytes) { $0["extra"] = true }))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(bytes) { $0["format"] = "future" }))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(bytes) { $0["kind"] = "delete" }))
    }
    func testDuplicateAndNoncanonicalHeadersAreRejected() throws {
        let original = try packet().data
        let size = original.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        let header = original.subdata(in: 4..<(4+size))
        for prefix in ["{ ", "{\"format\":\"orivyn.text.transfer.v1\","] {
            let changed = Data(prefix.utf8) + header.dropFirst()
            var size = UInt32(changed.count).bigEndian
            var bytes = withUnsafeBytes(of: &size) { Data($0) }
            bytes.append(changed); bytes.append(original.dropFirst(4+header.count))
            XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(bytes))
        }
    }
    func testFalsePayloadLengthAndWrongPayloadTypeAreRejected() throws {
        let bytes = try packet().data
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(bytes) { $0["payloadBytes"] = -1 }))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(bytes) { $0["payloadBytes"] = 5_000_001 }))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(bytes) { $0["kind"] = "receipt" }))
    }
    func testNoncanonicalAndEmptyRequestsAreRejected() throws {
        let id = identity(), digest = Data(repeating: 1, count: 32)
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.request(identity: id, payload: Data(), declaredSHA256: digest))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.request(identity: id, payload: try payload() + Data([32]), declaredSHA256: digest))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.request(identity: id, payload: Data(repeating: 0, count: 5_000_001), declaredSHA256: digest))
    }
    func testDuplicateReceiptSourcesAndEmptyReceiptAreRejected() throws {
        let row = TextRevisionReceiveSummary.Record(sourceID: UUID(), localID: UUID(), disposition: .inserted, preservedLocalID: nil)
        for records in [[], [row,row], Array(repeating: row, count: 101)] {
            XCTAssertThrowsError(try UnverifiedTextRevisionPacket.receipt(identity: identity(), requestSHA256: Data(repeating: 1, count: 32), summary: .init(records: records)))
        }
    }
    func testDigestRemainsExplicitlyUnverifiedUntilTransportChecksIt() throws {
        let original = try packet()
        let bytes = try replaceHeader(original.data) { $0["declaredSHA256"] = Data(repeating: 9, count: 32).base64EncodedString() }
        let decoded = try UnverifiedTextRevisionPacket.decode(bytes)
        XCTAssertNotEqual(decoded.declaredSHA256, original.declaredSHA256)
        XCTAssertEqual(decoded.payload, original.payload)
        // This parser is not authentication, consent, or permission to write.
    }
    func testBusyPacketIsExactRequestBoundNonAcknowledgement() throws {
        let id = identity(), digest = Data(repeating: 7, count: 32)
        let busy = try UnverifiedTextRevisionPacket.busy(identity: id, requestSHA256: digest)
        let decoded = try UnverifiedTextRevisionPacket.decode(busy.data)
        XCTAssertEqual(decoded.kind, .busy)
        XCTAssertEqual(decoded.identity, id)
        XCTAssertEqual(decoded.declaredSHA256, digest)
        XCTAssertEqual(decoded.payload, Data("busy".utf8))
        XCTAssertThrowsError(try decoded.receiptSummary())
    }
    func testBusyCannotContainSummaryArbitraryPayloadOrExtraFields() throws {
        let busy = try UnverifiedTextRevisionPacket.busy(identity: identity(), requestSHA256: Data(repeating: 7, count: 32))
        var malformed = Data(busy.data.dropLast(4)); malformed.append(Data("BUSY".utf8))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(malformed))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(busy.data + Data([0])))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(busy.data) { $0["extra"] = true }))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(busy.data) { $0["kind"] = "receipt" }))
        XCTAssertThrowsError(try UnverifiedTextRevisionPacket.decode(replaceHeader(busy.data) { $0["kind"] = "request" }))
    }

}
