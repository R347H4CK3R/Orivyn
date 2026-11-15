import Foundation

/// File selection is not approval to overwrite local history. A pending
/// replacement is consumed only by the explicit confirmation action.
struct BackupImportConfirmation {
    struct Request {
        let url: URL
        let policy: BackupImportPolicy
    }
    private(set) var pending: Request?
    private(set) var selectionID: UUID?
    private var selectionPolicy: BackupImportPolicy?
    private var active = true

    mutating func activate() { active = true }
    mutating func invalidate() {
        active = false
        cancel()
    }
    mutating func beginSelection(policy: BackupImportPolicy) -> UUID? {
        guard active, pending == nil else { return nil }
        // A system picker cancellation may dismiss without a result callback.
        // Starting a new presentation invalidates any prior callback.
        let token = UUID()
        selectionID = token
        selectionPolicy = policy
        return token
    }
    /// Consume only this presentation's result. A delayed callback cannot adopt
    /// a newer presentation's policy or recreate state after navigation away.
    mutating func finishSelection(_ token: UUID) -> BackupImportPolicy? {
        guard active, selectionID == token else { return nil }
        defer { selectionID = nil; selectionPolicy = nil }
        return selectionPolicy
    }

    mutating func select(_ url: URL, policy: BackupImportPolicy) -> Request? {
        guard active, pending == nil else { return nil }
        let request = Request(url: url, policy: policy)
        guard policy == .replaceMatching else { return request }
        pending = request
        return nil
    }

    mutating func confirm() -> Request? {
        defer { pending = nil }
        return pending
    }

    mutating func cancel() { pending = nil; selectionID = nil; selectionPolicy = nil }
}
