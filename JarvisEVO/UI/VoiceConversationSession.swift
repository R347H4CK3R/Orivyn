import Foundation

/// UI-owned bridge. Each controller keeps its own exact ticket, never a later
/// AppModel.activeVoiceTurn, when cancelling an asynchronous generation.
@MainActor
final class VoiceConversationSession {
    let controller: VoiceConversationController
    private let lease: VoiceTurnLease
    private let model: AppModel

    init(model: AppModel, audio: any VoiceConversationAudio) {
        self.model = model
        let lease = VoiceTurnLease()
        self.lease = lease
        controller = VoiceConversationController(voice: audio, sendText: { text in
            // onDraftChanged runs before this closure. Preflight tickets are not reused.
            let ticket = try model.makeVoiceTurnTicket(ownerID: lease.ownerID)
            lease.ticket = ticket
            if ticket.originatingConversationID != ticket.conversationID {
                lease.expectedSelection = (ticket.originatingConversationID, ticket.conversationID)
            }
            defer { if lease.ticket === ticket { lease.ticket = nil } }
            return try await model.sendVoice(text, ticket: ticket)
        }, cancelResponse: {
            guard let ticket = lease.ticket else { return }
            model.cancelVoiceTurn(ticket)
        })
        controller.onDraftChanged = { model.draft = $0 }
    }

    func start() throws {
        _ = try model.makeVoiceTurnTicket(ownerID: lease.ownerID)
        controller.start(draft: model.draft)
    }

    func stop() {
        controller.stop()
        lease.expectedSelection = nil
    }

    /// A first voice turn creates/selects its own conversation. That transition
    /// can reach SwiftUI after fast inference completes, so keep the exact pair.
    @discardableResult
    func selectionChanged(from oldID: UUID?, to newID: UUID?) -> Bool {
        if controller.isActive, let expected = lease.expectedSelection,
           expected.0 == oldID, expected.1 == newID {
            lease.expectedSelection = nil
            return true
        }
        stop()
        return false
    }
}

@MainActor
private final class VoiceTurnLease {
    let ownerID = UUID()
    var ticket: VoiceTurnTicket?
    var expectedSelection: (UUID?, UUID)?
}
