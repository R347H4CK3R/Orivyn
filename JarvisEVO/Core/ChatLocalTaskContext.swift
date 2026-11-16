import Foundation

/// Ephemeral review/run ownership, never durable approval or a source of actions.
struct ChatLocalTaskContext: Equatable, Sendable {
    let conversationID: UUID
    let conversationRevision: UUID
    let providerRevision: UUID
    func matches(conversationID: UUID?, conversationRevision: UUID, providerRevision: UUID) -> Bool {
        self.conversationID == conversationID && self.conversationRevision == conversationRevision && self.providerRevision == providerRevision
    }
}
