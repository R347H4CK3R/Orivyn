import Foundation

/// A distinct exact-base text protocol. These bytes are not authentication or
/// consent, and the legacy text outbox deliberately does not accept this format.
struct TextRevisionEnvelope: Sendable {
    struct Record: Codable, Equatable, Sendable {
        let base: Conversation?
        let incoming: Conversation
    }
    private struct Wire: Codable { let format: String; let records: [Record] }
    static let maximumBytes=5_000_000
    private static let format="orivyn.text.revisions.v1"
    let records: [Record]
    let data: Data

    init(records: [Record]) throws {
        guard (1...100).contains(records.count),Set(records.map { $0.incoming.id }).count==records.count else { throw ConversationError.invalidBackup }
        var messages=0
        for record in records {
            guard record.base == nil || record.base?.id==record.incoming.id else { throw ConversationError.invalidBackup }
            for conversation in [record.base,record.incoming].compactMap({ $0 }) {
                guard conversation.messages.count <= 1000-messages else { throw TextSnapshotError.limit };messages += conversation.messages.count
            }
        }
        _=try ReviewedTextSnapshot(conversations:records.map(\.incoming),exportedAt:Date(timeIntervalSince1970:0))
        let bases=records.compactMap(\.base)
        if !bases.isEmpty { _=try ReviewedTextSnapshot(conversations:bases,exportedAt:Date(timeIntervalSince1970:0)) }
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let bytes=try encoder.encode(Wire(format:Self.format,records:records))
        guard bytes.count<=Self.maximumBytes else { throw TextSnapshotError.limit }
        self.records=records;data=bytes
    }
    static func decodeCanonical(_ data: Data) throws -> Self {
        guard !data.isEmpty,data.count<=maximumBytes else { throw TextSnapshotError.limit }
        let wire=try JSONDecoder().decode(Wire.self,from:data)
        guard wire.format==format else { throw ConversationError.invalidBackup }
        let envelope=try Self(records:wire.records)
        // Reject ignored fields, duplicate keys, alternate field encodings and
        // whitespace: receipts bind the entire canonical ancestry+change envelope.
        guard envelope.data==data else { throw ConversationError.invalidBackup }
        return envelope
    }
    static func canonicalConversation(_ value: Conversation) throws -> Data {
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}

struct TextRevisionReceiveSummary: Codable, Equatable, Sendable {
    enum Disposition: String, Codable, Sendable { case inserted, advanced, unchanged, conflict }
    struct Record: Codable, Equatable, Sendable {
        let sourceID: UUID
        let localID: UUID
        let disposition: Disposition
        let preservedLocalID: UUID?
    }
    let records: [Record]
}
