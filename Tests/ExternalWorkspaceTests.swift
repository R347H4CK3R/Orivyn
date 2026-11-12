import XCTest
@testable import JarvisEVO

final class ExternalWorkspaceTests: XCTestCase {
    // Removing the connection gate must not let the phone claim it is presenting.
    func testSharingCannotStartWithoutDisplay() {
        var state = DeskPresentationState()
        state.startSharing()
        XCTAssertFalse(state.isSharing)
        XCTAssertFalse(state.canStartSharing)
        XCTAssertFalse(state.isConnected)
    }

    // Plugging a monitor in is not consent to reveal the conversation.
    func testConnectingRequiresSeparateDisclosure() {
        var state = DeskPresentationState()
        state.connect(sessionID: "monitor-a")
        XCTAssertTrue(state.isConnected)
        XCTAssertTrue(state.canStartSharing)
        XCTAssertFalse(state.isSharing)
        state.startSharing()
        XCTAssertTrue(state.isSharing)
        state.stopSharing()
        XCTAssertFalse(state.isSharing)
        XCTAssertTrue(state.isConnected)
    }

    // Returning from lock/background must not silently reveal private content.
    func testInactiveClearsSharingAndForegroundDoesNotRestoreIt() {
        var state = DeskPresentationState()
        state.connect(sessionID: "monitor-a")
        state.startSharing()
        state.setForeground(false)
        XCTAssertFalse(state.isSharing)
        XCTAssertFalse(state.canStartSharing)
        state.startSharing()
        XCTAssertFalse(state.isSharing)
        state.setForeground(true)
        XCTAssertTrue(state.canStartSharing)
        XCTAssertFalse(state.isSharing)
    }

    // A replacement display must never inherit the previous display's reveal.
    func testDisconnectReconnectRequiresNewDisclosureAndPreservesPanel() {
        var state = DeskPresentationState()
        state.select(.projects)
        state.connect(sessionID: "monitor-a")
        state.startSharing()
        state.disconnect(sessionID: "monitor-a")
        XCTAssertFalse(state.isConnected)
        XCTAssertFalse(state.isSharing)
        state.connect(sessionID: "monitor-b")
        XCTAssertFalse(state.isSharing)
        XCTAssertEqual(state.selectedPanel, .projects)
    }

    // A second actual display changes the audience and revokes existing disclosure.
    func testNewDisplayRevokesSharingButDuplicateLifecycleDoesNot() {
        var state = DeskPresentationState()
        state.connect(sessionID: "monitor-a")
        state.startSharing()
        state.connect(sessionID: "monitor-a")
        XCTAssertTrue(state.isSharing)
        state.connect(sessionID: "monitor-b")
        XCTAssertFalse(state.isSharing)
        XCTAssertEqual(state.connectedDisplayCount, 2)
    }

    // A stale disconnect must not remove another scene or interrupt its disclosure.
    func testUnknownDisconnectDoesNotChangeConnectedScene() {
        var state = DeskPresentationState()
        state.connect(sessionID: "monitor-a")
        state.startSharing()
        state.disconnect(sessionID: "stale")
        XCTAssertTrue(state.isSharing)
        XCTAssertEqual(state.connectedDisplayCount, 1)
    }

    func testDisconnectOneOfTwoDisplaysHidesRemainingDisplay() {
        var state = DeskPresentationState()
        state.connect(sessionID: "monitor-a")
        state.connect(sessionID: "monitor-b")
        state.startSharing()
        state.disconnect(sessionID: "monitor-a")
        XCTAssertTrue(state.isConnected)
        XCTAssertFalse(state.isSharing)
        XCTAssertEqual(state.connectedDisplayCount, 1)
    }

    // Changing panels is a phone action, not a grant of disclosure permission.
    func testPanelSelectionDoesNotRevealContent() {
        var state = DeskPresentationState()
        state.connect(sessionID: "monitor-a")
        state.select(.models)
        XCTAssertEqual(state.selectedPanel, .models)
        XCTAssertFalse(state.isSharing)
    }
}
