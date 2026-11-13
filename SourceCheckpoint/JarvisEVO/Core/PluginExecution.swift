import Foundation

struct PluginCallReview: Identifiable, Sendable {
    let id: UUID
    let connectionID: UUID
    let catalogRevision: UUID
    let toolName: String
    let arguments: MCPJSONValue
    let createdAt: Date
}

/// An approval is an immutable, expiring capability for exactly one reviewed call.
/// This gate cannot send a request or infer permission from remote annotations.
struct PluginReviewGate {
    private var pending: PluginCallReview?
    mutating func prepare(connectionID: UUID, catalogRevision: UUID, toolName: String,
                          arguments: MCPJSONValue, now: Date = Date()) throws -> PluginCallReview {
        invalidate()
        guard Self.validName(toolName), now.timeIntervalSince1970.isFinite,
              case .object = arguments else { throw PluginExecutionError.invalidReview }
        _ = try arguments.encoded(maximumBytes: 16_384)
        let review = PluginCallReview(id: UUID(), connectionID: connectionID, catalogRevision: catalogRevision,
                                     toolName: toolName, arguments: arguments, createdAt: now)
        pending = review
        return review
    }
    mutating func consume(id: UUID, connectionID: UUID, catalogRevision: UUID, now: Date = Date()) throws -> PluginCallReview {
        let value = pending
        invalidate() // Any failed attempt invalidates the capability too.
        guard let value, value.id == id, value.connectionID == connectionID,
              value.catalogRevision == catalogRevision else { throw PluginExecutionError.staleReview }
        let age = now.timeIntervalSince(value.createdAt)
        guard age.isFinite, age >= 0, age <= 300 else { throw PluginExecutionError.staleReview }
        return value
    }
    mutating func invalidate() { pending = nil }
    static func validName(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 128
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

}

enum PluginExecutionState: String, Codable, Sendable {
    case running, serverReportedSuccess, serverReportedError, localFailure, unknown
    var title: String {
        switch self {
        case .running: "Running"
        case .serverReportedSuccess: "Server reported completion"
        case .serverReportedError: "Server reported a tool error"
        case .localFailure: "Failed before execution"
        case .unknown: "Outcome unknown · do not retry blindly"
        }
    }
}
struct PluginExecutionRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let connectionID: UUID
    let toolName: String
    let createdAt: Date
    var state: PluginExecutionState
}

enum PluginExecutionError: LocalizedError {
    case invalidReview, staleReview, invalidJournal, missingRecord, journalFull, outcomeNotRecorded
    var errorDescription: String? {
        switch self {
        case .invalidReview: "The tool name or arguments exceed the safe review limits. Nothing was sent."
        case .staleReview: "This review expired or the connection, tool or arguments changed. Review the exact call again. Nothing was sent."
        case .invalidJournal: "The plugin execution log could not be read safely. Existing data was preserved; tool execution is disabled."
        case .missingRecord: "This execution no longer has a running record. Its outcome was not changed."
        case .journalFull: "The execution log is full of unresolved operations. Resolve their outcomes before starting another call."
        case .outcomeNotRecorded: "The server may have acted, but its outcome could not be saved. New calls are disabled. Preserve the log, restore writable storage and reopen Orivyn for recovery. Check the server before retrying the action."
        }
    }
}
