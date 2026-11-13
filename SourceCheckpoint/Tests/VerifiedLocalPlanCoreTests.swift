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
    }    func testNaturalLanguageRoutingIsOnlyAReviewedProposal() throws {
        let core = try VerifiedLocalPlanCore()
        let matched = try core.route("What app is this and what models are installed?")
        XCTAssertEqual(matched.status, "matched")
        XCTAssertEqual(matched.request?.appInfo, true)
        XCTAssertEqual(matched.request?.installedModels, true)
        let unsupported = try core.route("What app is this and delete my files")
        XCTAssertNil(unsupported.request)
        XCTAssertNotEqual(unsupported.status, "matched")
    }

}
