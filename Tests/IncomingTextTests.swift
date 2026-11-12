import XCTest
import AppIntents
@testable import JarvisEVO

@MainActor
final class IncomingTextTests: XCTestCase {
    func testURLDecodesExactlyOnceAndPreservesLiteralPlusWhitespaceAndUnicode() throws {
        let request = try IncomingTextRequest.parse(XCTUnwrap(URL(string: "orivyn://compose?text=%20caf%C3%A9%20%2B%20%252F%0A")))
        XCTAssertEqual(request.text, " café + %2F\n")
        XCTAssertEqual(try IncomingTextRequest.parse(XCTUnwrap(URL(string: "orivyn://compose?text=a+b"))).text, "a+b")
    }

    func testRejectsOtherRoutesCredentialsPortsFragmentsAndAmbiguousParameters() throws {
        for value in [
            "https://compose?text=hi", "orivyn://send?text=hi", "orivyn://compose/path?text=hi",
            "orivyn://user@compose?text=hi", "orivyn://user:password@compose?text=hi",
            "orivyn://compose:443?text=hi", "orivyn://compose?text=hi#fragment",
            "orivyn://compose?text=hi&text=second", "orivyn://compose?text=hi&send=true",
            "orivyn://compose?Text=hi", "orivyn://compose", "orivyn://compose?text",
            "orivyn://compose?text=", "orivyn://compose?text=%20%0A", "orivyn://compose?text=%00"
        ] {
            XCTAssertThrowsError(try IncomingTextRequest.parse(XCTUnwrap(URL(string: value))), value)
        }
    }

    func testInputLimitIsUTF8BytesAndNeverTruncates() throws {
        let atLimit = String(repeating: "😀", count: 2_048)
        XCTAssertEqual(try IncomingTextRequest(text: atLimit).text, atLimit)
        XCTAssertThrowsError(try IncomingTextRequest(text: atLimit + "a"))
        XCTAssertThrowsError(try IncomingTextRequest(text: "\0hello"))
        XCTAssertThrowsError(try IncomingTextRequest(text: " \n\t"))
        XCTAssertThrowsError(try IncomingTextRequest.parse(XCTUnwrap(URL(string: "orivyn://compose?text=" + String(repeating: "a", count: 32_768)))))
    }

    func testAppendKeepsCurrentDraftAndRejectsOverflowAtomically() throws {
        XCTAssertEqual(try IncomingTextRequest.appending("New", to: "Old \n"), "Old \n\n\nNew")
        XCTAssertEqual(try IncomingTextRequest.appending("New", to: ""), "New")
        let atLimit = String(repeating: "x", count: 32_765)
        XCTAssertEqual(try IncomingTextRequest.appending("y", to: atLimit).utf8.count, 32_768)
        XCTAssertThrowsError(try IncomingTextRequest.appending("yy", to: atLimit))
    }

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
