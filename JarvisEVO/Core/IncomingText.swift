import Foundation
import Observation

/// In-process, foreground-only staging. Never stores shared text to disk or logs it.
@MainActor @Observable
final class IncomingTextInbox {
    static let shared = IncomingTextInbox()
    private(set) var pending: IncomingTextRequest?
    private(set) var lastError: String?

    @discardableResult func enqueue(_ text: String) throws -> IncomingTextRequest {
        guard pending == nil else { throw IncomingTextError.pendingRequest }
        let request = try IncomingTextRequest(text: text)
        pending = request
        lastError = nil
        return request
    }

    func receive(_ url: URL) {
        do { _ = try enqueue(IncomingTextRequest.parse(url).text) }
        catch { lastError = error.localizedDescription }
    }

    func discard(id: UUID) {
        guard pending?.id == id else { return }
        pending = nil
        lastError = nil
    }
    func dismissError() { lastError = nil }
}
