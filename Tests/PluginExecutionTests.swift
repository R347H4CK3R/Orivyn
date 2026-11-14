import XCTest
@testable import JarvisEVO

final class PluginExecutionTests: XCTestCase {
    private let connection = UUID()
    private let revision = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReviewCopiesExactArgumentsAndCanBeConsumedOnlyOnce() throws {
        var gate = PluginReviewGate()
        let arguments = MCPJSONValue.object(["text": .string("Only this explicit text")])
        let review = try gate.prepare(connectionID: connection, catalogRevision: revision,
            toolName: "workspace.read", arguments: arguments, now: now)
        let consumed = try gate.consume(id: review.id, connectionID: connection, catalogRevision: revision, now: now)
        XCTAssertEqual(consumed.arguments, arguments)
        XCTAssertEqual(consumed.toolName, "workspace.read")
        XCTAssertEqual(consumed.connectionID, connection)
        XCTAssertThrowsError(try gate.consume(id: review.id, connectionID: connection, catalogRevision: revision, now: now))
    }

    func testChangingConnectionOrCatalogCannotReuseApproval() throws {
        for changeConnection in [true, false] {
            var gate = PluginReviewGate()
            let review = try gate.prepare(connectionID: connection, catalogRevision: revision,
                toolName: "tool", arguments: .object([:]), now: now)
            XCTAssertThrowsError(try gate.consume(id: review.id,
                connectionID: changeConnection ? UUID() : connection,
                catalogRevision: changeConnection ? revision : UUID(), now: now))
        }
    }

    func testNewReviewInvalidatesOldEvenWhenArgumentsAreLaterRestored() throws {
        var gate = PluginReviewGate()
        let first = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        _ = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "b", arguments: .object([:]), now: now)
        let third = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertNotEqual(first.id, third.id)
        XCTAssertThrowsError(try gate.consume(id: first.id, connectionID: connection, catalogRevision: revision, now: now))
    }

    func testExplicitInvalidationAndExpiryNeverReturnApproval() throws {
        var gate = PluginReviewGate()
        let first = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        gate.invalidate()
        XCTAssertThrowsError(try gate.consume(id: first.id, connectionID: connection, catalogRevision: revision, now: now))
        let expired = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertThrowsError(try gate.consume(id: expired.id, connectionID: connection, catalogRevision: revision, now: now.addingTimeInterval(301)))
    }

    func testExactFiveMinuteBoundaryIsAcceptedButClockReversalIsNot() throws {
        var gate = PluginReviewGate()
        let edge = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertNoThrow(try gate.consume(id: edge.id, connectionID: connection, catalogRevision: revision, now: now.addingTimeInterval(300)))
        let reversed = try gate.prepare(connectionID: connection, catalogRevision: revision, toolName: "a", arguments: .object([:]), now: now)
        XCTAssertThrowsError(try gate.consume(id: reversed.id, connectionID: connection, catalogRevision: revision, now: now.addingTimeInterval(-1)))
    }

    func testOversizedArgumentsAndUnsafeNamesAreRejectedWithoutReview() {
        var gate = PluginReviewGate()
        XCTAssertThrowsError(try gate.prepare(connectionID: connection, catalogRevision: revision,
            toolName: "tool", arguments: .object(["value": .string(String(repeating: "x", count: 16_384))]), now: now))
        for name in ["", "tool\nname", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try gate.prepare(connectionID: connection, catalogRevision: revision,
                toolName: name, arguments: .object([:]), now: now))
        }
    }
}
