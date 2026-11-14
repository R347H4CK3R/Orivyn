import XCTest
import AppIntents
@testable import JarvisEVO

@MainActor
final class IncomingTextTests: XCTestCase {
    func testSecondRequestAndStaleDismissCannotReplaceOrRemovePendingText() throws {
        let inbox = IncomingTextInbox()
        let first = try inbox.enqueue("First")
        XCTAssertThrowsError(try inbox.enqueue("Second"))
        XCTAssertEqual(inbox.pending, first)
        inbox.discard(id: UUID())
        XCTAssertEqual(inbox.pending, first)
        inbox.discard(id: first.id)
        XCTAssertNil(inbox.pending)
        XCTAssertEqual(try inbox.enqueue("Third").text, "Third")
    }

    func testRejectedURLReportsErrorWithoutDiscardingPreviousRequest() throws {
        let inbox = IncomingTextInbox()
        let first = try inbox.enqueue("First")
        inbox.receive(try XCTUnwrap(URL(string: "orivyn://send?text=Second")))
        XCTAssertEqual(inbox.pending, first)
        XCTAssertNotNil(inbox.lastError)
        inbox.dismissError()
        XCTAssertNil(inbox.lastError)
        XCTAssertEqual(inbox.pending, first)
    }

    func testAppIntentStagesTextWithoutSendingAndPreservesExistingRequest() async throws {
        let inbox = IncomingTextInbox.shared
        if let pending = inbox.pending { inbox.discard(id: pending.id) }
        defer { if let pending = inbox.pending { inbox.discard(id: pending.id) } }
        _ = try await ComposeInOrivynIntent(text: "Review this first").perform()
        XCTAssertEqual(inbox.pending?.text, "Review this first")
        do {
            _ = try await ComposeInOrivynIntent(text: "Do not replace").perform()
            XCTFail("A second shortcut must not replace the pending request")
        } catch { XCTAssertEqual(error as? IncomingTextError, .pendingRequest) }
        XCTAssertEqual(inbox.pending?.text, "Review this first")
    }
}
