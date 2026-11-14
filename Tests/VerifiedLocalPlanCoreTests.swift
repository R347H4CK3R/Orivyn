import XCTest
@testable import JarvisEVO

@MainActor
final class VerifiedLocalPlanCoreTests: XCTestCase {
    func testExactPlanDoesNotUseAChosenModelOrInventAnAnswer() throws {
        let core = try VerifiedLocalPlanCore()
        let state = try core.call("create", [#"{"appInfo":true,"installedModels":true,"searchQuery":null}"#, UUID().uuidString])
        let pending = try core.call("next", [state])
        XCTAssertEqual(try core.snapshot(pending).pending?.name, "get_app_info")
        XCTAssertEqual(try core.snapshot(pending).completed, 0)
        XCTAssertTrue(try core.call("report", [pending]).contains("\"complete\":false"))
        let recovered = try core.call("recover", [pending])
        XCTAssertEqual(try core.snapshot(recovered).status, "interrupted")
        let resumed = try core.call("resume", [recovered])
        let retry = try core.call("next", [resumed])
        XCTAssertNotEqual(try core.snapshot(retry).pending?.operationID, try core.snapshot(pending).pending?.operationID)
    }
    func testEmptyPlanAndUnknownPermissionsAreRejected() throws {
        let core = try VerifiedLocalPlanCore()
        XCTAssertThrowsError(try core.call("create", [#"{"appInfo":false,"installedModels":false,"searchQuery":null}"#, UUID().uuidString]))
        XCTAssertThrowsError(try core.call("create", [#"{"appInfo":true,"installedModels":false,"searchQuery":null,"sendEmail":true}"#, UUID().uuidString]))
    }

    func testNaturalLanguageRoutingIsOnlyAReviewedProposal() throws {
        let core = try VerifiedLocalPlanCore()
        let matched = try core.route("What app is this and what models are installed?")
        XCTAssertEqual(matched.status, "matched")
        XCTAssertEqual(matched.request?.appInfo, true)
        XCTAssertEqual(matched.request?.installedModels, true)
        let unsupported = try core.route("What app is this and delete my files")
        XCTAssertNil(unsupported.request)
        XCTAssertNotEqual(unsupported.status, "matched")
    }

    func testSequentialProposalPreservesQueriesAndRejectsMixedActions() throws {
        let core = try VerifiedLocalPlanCore()
        let proposed = try core.route("Read app information; list installed local models")
        XCTAssertEqual(proposed.status, "matched")
        XCTAssertEqual(proposed.request?.appInfo, true)
        XCTAssertEqual(proposed.request?.installedModels, true)
        XCTAssertTrue(proposed.message.contains("not the order typed"))
        let query = try core.route("Search conversations for \"USB; then restore\" then read app info")
        XCTAssertEqual(query.request?.searchQuery, "USB; then restore")
        for suffix in ["delete files", "do not list installed models", "install another model"] {
            let rejected = try core.route("Read app info then " + suffix)
            XCTAssertNil(rejected.request)
            XCTAssertNotEqual(rejected.status, "matched")
        }
    }

    func testTwoReadPlanRequiresModelEvidenceNotAssistantName() throws {
        let core = try VerifiedLocalPlanCore()
        var state = try core.call("create", [#"{"appInfo":true,"installedModels":true,"searchQuery":null,"memoryQuery":null}"#, UUID().uuidString])
        let fixtures = [
            #"{"app":"Orivyn","assistant":"Jarvis","repository":"fixture","repositoryAccess":"synthetic","capabilities":[]}"#,
            #"{"models":[{"id":"fixture-model","name":"Installed fixture model"}],"totalInstalled":1,"truncated":false}"#
        ]
        for (index, result) in fixtures.enumerated() {
            state = try core.call("next", [state])
            let snapshot = try core.snapshot(state)
            XCTAssertEqual(snapshot.pending?.name, index == 0 ? "get_app_info" : "list_models")
            let operation = try XCTUnwrap(snapshot.pending?.operationID)
            let envelope = try JSONSerialization.data(withJSONObject: ["operationID": operation, "resultJSON": result])
            state = try core.call("record", [state, String(decoding: envelope, as: UTF8.self)])
            XCTAssertEqual(try core.snapshot(state).status, index == 0 ? "ready" : "complete")
        }
        XCTAssertEqual(try core.snapshot(state).completed, 2)
        let report = try core.call("report", [state])
        XCTAssertTrue(report.contains("Installed fixture model"))
        XCTAssertTrue(report.contains("\"complete\":true"))
    }

}
