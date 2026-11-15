// Experimental one-shot exchange. Disabled in the shipping application.
// The caller must own reviewed scope, pairing lifecycle and task cancellation.
#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit)
import Foundation
import CryptoKit

enum PeerTextRevisionExchange {
    enum Failure: Error { case invalidScope, invalidRequest, invalidReceipt, missingTransfer }

    static func send(transferID: UUID, store: SQLiteConversationStore,
                     over channel: PeerTLSProbe.AuthenticatedChannel) async throws -> TextRevisionReceiveSummary {
        try await withTaskCancellationHandler {
            defer { channel.cancel() }
            try Task.checkCancellation()
            guard let staged = try await store.textRevisionSend(id: transferID), !staged.delivered else {
                throw Failure.missingTransfer
            }
            let identity = staged.identity
            guard identity.senderCertificateSHA256 == channel.localCertificateSHA256,
                  identity.receiverCertificateSHA256 == channel.peerCertificateSHA256,
                  identity.pairingGeneration == channel.pairingGeneration else { throw Failure.invalidScope }
            let digest = Data(SHA256.hash(data: staged.payload))
            let request = try UnverifiedTextRevisionPacket.request(identity: identity, payload: staged.payload, declaredSHA256: digest)
            try Task.checkCancellation()
            try await write(request.data, channel: channel)
            let receipt = try UnverifiedTextRevisionPacket.decode(await read(channel))
            guard receipt.kind == .receipt, receipt.identity == identity,
                  receipt.declaredSHA256 == digest else { throw Failure.invalidReceipt }
            let summary = try receipt.receiptSummary()
            try Task.checkCancellation()
            // The database rechecks revocation and staged ancestry atomically.
            try await store.recordTextRevisionDeliveryReceipt(identity: identity, payload: staged.payload, summary: summary)
            return summary
        } onCancel: {
            channel.cancel()
        }
    }

    static func receive(approvedSourceIDs: Set<UUID>, expectedEpoch: UUID,
                        store: SQLiteConversationStore,
                        over channel: PeerTLSProbe.AuthenticatedChannel) async throws -> TextRevisionReceiveSummary {
        try await withTaskCancellationHandler {
            defer { channel.cancel() }
            try Task.checkCancellation()
            guard (1...100).contains(approvedSourceIDs.count) else { throw Failure.invalidScope }
            let request = try UnverifiedTextRevisionPacket.decode(await read(channel))
            let identity = request.identity
            guard request.kind == .request,
                  identity.senderCertificateSHA256 == channel.peerCertificateSHA256,
                  identity.receiverCertificateSHA256 == channel.localCertificateSHA256,
                  identity.pairingGeneration == channel.pairingGeneration,
                  identity.receiverEpoch == expectedEpoch,
                  Data(SHA256.hash(data: request.payload)) == request.declaredSHA256 else {
                throw Failure.invalidRequest
            }
            let envelope = try TextRevisionEnvelope.decodeCanonical(request.payload)
            guard Set(envelope.records.map { $0.incoming.id }).isSubset(of: approvedSourceIDs) else {
                throw Failure.invalidScope
            }
            try Task.checkCancellation()
            // Commit before acknowledging. Epoch, revocation, exact ancestry and
            // local edits are checked in the receiver's transaction.
            let summary = try await store.receiveReviewedTextRevisions(request.payload, identity: identity.receiveIdentity)
            try Task.checkCancellation()
            let receipt = try UnverifiedTextRevisionPacket.receipt(identity: identity,
                requestSHA256: request.declaredSHA256, summary: summary)
            try await write(receipt.data, channel: channel)
            // A lost receipt leaves the sender pending. Retry uses the durable
            // receiver receipt; it must never manufacture a new import.
            return summary
        } onCancel: {
            channel.cancel()
        }
    }

    private static func write(_ data: Data, channel: PeerTLSProbe.AuthenticatedChannel) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.send(data) { continuation.resume(with: $0) }
        }
    }

    private static func read(_ channel: PeerTLSProbe.AuthenticatedChannel) async throws -> Data {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            channel.receive { continuation.resume(with: $0) }
        }
    }
}
#endif
