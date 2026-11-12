import XCTest
@testable import JarvisEVO

final class AttachmentPickerOwnershipTests: XCTestCase {
    func testCancelledPickerCannotDeliverIntoReopenedPickerInSameConversation() {
        let context = UUID()
        let old = AttachmentPickerRequest(context: context, kind: .photos, limit: 4)
        let current = AttachmentPickerRequest(context: context, kind: .photos, limit: 4)
        var owner = AttachmentPickerOwnership()
        owner.open(old); owner.cancel(id: old.id); owner.open(current)
        XCTAssertFalse(owner.consume(old, currentContext: context))
        XCTAssertEqual(owner.activeID, current.id)
        XCTAssertTrue(owner.consume(current, currentContext: context))
    }

    func testNewConversationRejectsOldRequestEvenBeforeItsDismissalCallback() {
        let old = AttachmentPickerRequest(context: UUID(), kind: .files, limit: 4)
        var owner = AttachmentPickerOwnership()
        owner.open(old)
        XCTAssertFalse(owner.consume(old, currentContext: UUID()))
        XCTAssertNil(owner.activeID)
    }

    func testLateCancelDoesNotCancelLaterCameraPresentation() {
        let context = UUID()
        let old = AttachmentPickerRequest(context: context, kind: .photos, limit: 4)
        let camera = AttachmentPickerRequest(context: context, kind: .camera, limit: 1)
        var owner = AttachmentPickerOwnership()
        owner.open(old); owner.open(camera); owner.cancel(id: old.id)
        XCTAssertEqual(owner.activeID, camera.id)
        XCTAssertTrue(owner.consume(camera, currentContext: context))
    }

    func testSuccessfulCallbackIsConsumedExactlyOnce() {
        let request = AttachmentPickerRequest(context: UUID(), kind: .files, limit: 4)
        var owner = AttachmentPickerOwnership()
        owner.open(request)
        XCTAssertTrue(owner.consume(request, currentContext: request.context))
        XCTAssertFalse(owner.consume(request, currentContext: request.context))
    }
}
