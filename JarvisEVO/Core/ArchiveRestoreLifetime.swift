import Foundation

/// Revocation token captured by each archive picker callback. A removed host or
/// background transition cannot be reauthorized by a later view's appearance.
@MainActor
final class ArchiveRestoreLifetime {
    private(set) var isValid = true
    func invalidate() { isValid = false }
}
