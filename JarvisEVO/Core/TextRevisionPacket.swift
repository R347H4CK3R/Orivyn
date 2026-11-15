import Foundation

/// Strict wire parsing only. This value NEVER proves authentication, digest
/// validity, consent, current epoch, or authority to mutate persistence. The live
/// adapter must verify every field against its actual authenticated channel and
/// recompute SHA-256 before calling the database. No adapter is enabled yet.
struct UnverifiedTextRevisionPacket: Sendable {
    enum Kind: String, Codable, Sendable { case request, receipt, busy }
    private struct Header: Codable, Sendable {
        let format: String
        let kind: Kind
        let receiverEpoch: UUID
        let transfer: UUID
        let senderCertificateSHA256: Data
        let receiverCertificateSHA256: Data
        let pairingGeneration: UUID
        let declaredSHA256: Data
        let payloadBytes: Int
    }
    static let maximumHeaderBytes = 1020
    static let maximumPacketBytes = 5_001_024
    private static let format = "orivyn.text.transfer.v1"
    private static let maximumReceiptBytes = 65_536
    private let header: Header
    let payload: Data
    let data: Data
    var kind: Kind { header.kind }
    var declaredSHA256: Data { header.declaredSHA256 }
    var identity: TextSendIdentity {
        .init(receiverEpoch: header.receiverEpoch, transfer: header.transfer,
              senderCertificateSHA256: header.senderCertificateSHA256,
              receiverCertificateSHA256: header.receiverCertificateSHA256,
              pairingGeneration: header.pairingGeneration)
    }

    static func request(identity: TextSendIdentity, payload: Data, declaredSHA256: Data) throws -> Self {
        try Self(kind: .request, identity: identity, payload: payload, digest: declaredSHA256)
    }

    static func receipt(identity: TextSendIdentity, requestSHA256: Data, summary: TextRevisionReceiveSummary) throws -> Self {
        try validateSummary(summary)
        return try Self(kind: .receipt, identity: identity, payload: canonical(summary), digest: requestSHA256)
    }

    /// A bounded non-acknowledgement tied to the exact request. This never
    /// advances delivery or revision ancestry.
    static func busy(identity: TextSendIdentity, requestSHA256: Data) throws -> Self {
        try Self(kind: .busy, identity: identity, payload: Data("busy".utf8), digest: requestSHA256)
    }

    private init(kind: Kind, identity: TextSendIdentity, payload: Data, digest: Data) throws {
        let header = Header(format: Self.format, kind: kind, receiverEpoch: identity.receiverEpoch,
            transfer: identity.transfer, senderCertificateSHA256: identity.senderCertificateSHA256,
            receiverCertificateSHA256: identity.receiverCertificateSHA256, pairingGeneration: identity.pairingGeneration,
            declaredSHA256: digest, payloadBytes: payload.count)
        try Self.validate(header: header, payload: payload)
        let encoded = try Self.canonical(header)
        guard (1...Self.maximumHeaderBytes).contains(encoded.count) else { throw ConversationError.invalidBackup }
        var length = UInt32(encoded.count).bigEndian
        var bytes = withUnsafeBytes(of: &length) { Data($0) }
        bytes.append(encoded); bytes.append(payload)
        guard bytes.count <= Self.maximumPacketBytes else { throw TextSnapshotError.limit }
        self.header = header; self.payload = payload; self.data = bytes
    }

    static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count >= 5, bytes.count <= maximumPacketBytes else { throw TextSnapshotError.limit }
        let headerCount = bytes.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (1...maximumHeaderBytes).contains(headerCount), headerCount <= bytes.count - 4 else {
            throw ConversationError.invalidBackup
        }
        // Data slices retain their original startIndex. Wire offsets are relative
        // to this packet, not absolute indices in the backing receive buffer.
        let headerBytes = Data(bytes.dropFirst(4).prefix(headerCount))
        let header = try JSONDecoder().decode(Header.self, from: headerBytes)
        guard try canonical(header) == headerBytes else { throw ConversationError.invalidBackup }
        let payload = Data(bytes.dropFirst(4 + headerCount))
        try validate(header: header, payload: payload)
        let value = try Self(kind: header.kind,
            identity: .init(receiverEpoch: header.receiverEpoch, transfer: header.transfer,
                senderCertificateSHA256: header.senderCertificateSHA256,
                receiverCertificateSHA256: header.receiverCertificateSHA256,
                pairingGeneration: header.pairingGeneration),
            payload: payload, digest: header.declaredSHA256)
        guard value.data == bytes else { throw ConversationError.invalidBackup }
        return value
    }

    func receiptSummary() throws -> TextRevisionReceiveSummary {
        guard kind == .receipt else { throw ConversationError.invalidBackup }
        return try JSONDecoder().decode(TextRevisionReceiveSummary.self, from: payload)
    }

    private static func validate(header: Header, payload: Data) throws {
        guard header.format == format,
              header.senderCertificateSHA256.count == 32, header.receiverCertificateSHA256.count == 32,
              header.senderCertificateSHA256 != header.receiverCertificateSHA256,
              header.declaredSHA256.count == 32, header.payloadBytes == payload.count,
              !payload.isEmpty else { throw ConversationError.invalidBackup }
        switch header.kind {
        case .request:
            _ = try TextRevisionEnvelope.decodeCanonical(payload)
        case .busy:
            guard payload == Data("busy".utf8) else { throw ConversationError.invalidBackup }
        case .receipt:
            guard payload.count <= maximumReceiptBytes else { throw TextSnapshotError.limit }
            let summary = try JSONDecoder().decode(TextRevisionReceiveSummary.self, from: payload)
            try validateSummary(summary)
            guard try canonical(summary) == payload else { throw ConversationError.invalidBackup }
        }
    }

    private static func validateSummary(_ summary: TextRevisionReceiveSummary) throws {
        guard (1...100).contains(summary.records.count),
              Set(summary.records.map(\.sourceID)).count == summary.records.count,
              Set(summary.records.map(\.localID)).count == summary.records.count else { throw ConversationError.invalidBackup }
        for row in summary.records {
            guard (row.disposition == .conflict) == (row.preservedLocalID != nil),
                  row.preservedLocalID != row.localID else { throw ConversationError.invalidBackup }
        }
    }

    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}
