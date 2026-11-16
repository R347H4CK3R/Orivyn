import XCTest
@testable import JarvisEVO
final class ChatLocalTaskContextTests: XCTestCase {
    func testRejectsConversationAndProviderRevisionChanges() {
        let c = UUID(), r = UUID(), p = UUID()
        let context = ChatLocalTaskContext(conversationID: c, conversationRevision: r, providerRevision: p)
        XCTAssertTrue(context.matches(conversationID: c, conversationRevision: r, providerRevision: p))
        XCTAssertFalse(context.matches(conversationID: nil, conversationRevision: r, providerRevision: p))
        XCTAssertFalse(context.matches(conversationID: UUID(), conversationRevision: r, providerRevision: p))
        XCTAssertFalse(context.matches(conversationID: c, conversationRevision: UUID(), providerRevision: p))
        XCTAssertFalse(context.matches(conversationID: c, conversationRevision: r, providerRevision: UUID()))
    }
}
