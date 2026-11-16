import Foundation

/// Reconciles filesystem preparation state with authoritative database receipts.
/// A confirmed receipt hides the preparation even if filesystem maintenance fails.
enum ArchiveRestoreRecovery {
    struct Result: Sendable {
        var ready: [ArchiveRestoreService.Review] = []
        var committedJobs: [UUID] = []
        var maintenancePending: [UUID] = []
    }
    @MainActor static func reconcile(_ reviews: [ArchiveRestoreService.Review],
                          isCommitted: (String) async throws -> Bool,
                          markCommitted: (ArchiveRestoreService.Review) async throws -> Void) async throws -> Result {
        var result = Result()
        for review in reviews {
            try Task.checkCancellation()
            // Lookup failure is not evidence of an uncommitted preparation.
            guard try await isCommitted(review.archiveSHA256) else {
                result.ready.append(review); continue
            }
            result.committedJobs.append(review.jobID)
            do { try await markCommitted(review) }
            catch { result.maintenancePending.append(review.jobID) }
        }
        return result
    }
}
