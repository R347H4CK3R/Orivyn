import XCTest
@testable import JarvisEVO

final class LocalAgentVersionRoutingTests: XCTestCase {
    private func raw(_ fields: String) -> String {
        #"{"id":"12345678-1234-1234-1234-123456789abc","goal":"Inspect local data","status":"ready","revision":0,"steps":0,"history":[],"pending":null,"answer":null,"error":null,"internalReads":0,"resultView":null,"exposedThrough":[],"# + fields + "}"
    }
    private func decode(_ fields: String) throws -> LocalAgentSnapshot {
        try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(raw(fields).utf8))
    }
    func testUnknownOrMissingVersionCannotRouteAsGeneric() throws {
        for fields in [#""version":4"#, #""version":0"#, #""version":true"#, #""version":"1""#, #""unused":1"#] {
            XCTAssertThrowsError(try decode(fields), fields)
        }
    }
    func testRecoveredContractMissingOrMalformedNeverRoutesAsGeneric() throws {
        for fields in [#""version":3"#, #""version":3,"approvalRevision":0"#, #""version":3,"approvalRevision":0,"completionContract":{"schema":1,"steps":[]}"#, #""version":3,"approvalRevision":0,"completionContract":{"schema":1,"steps":[{"name":"calculate","arguments":{"expression":"1+1"}}]}"#] {
            XCTAssertThrowsError(try decode(fields), fields)
        }
    }
    func testExistingVersionsRejectMixedScopeMetadata() throws {
        let contract = #""completionContract":{"schema":1,"steps":[{"name":"list_models","arguments":{}}]}"#
        XCTAssertThrowsError(try decode(#""version":1,"# + contract))
        XCTAssertThrowsError(try decode(#""version":2,"approvalRevision":0,"# + contract))
        XCTAssertThrowsError(try decode(#""version":2"#))
        XCTAssertThrowsError(try decode(#""version":1,"approvalRevision":0"#))
        XCTAssertNoThrow(try decode(#""version":1"#))
        XCTAssertNoThrow(try decode(#""version":2,"approvalRevision":0,"readPlan":{"schema":1,"kind":"conversation_search","query":"Cedar"}"#))
    }
    func testValidV3RetainsVersionAndContractWithoutLegacyPlan() throws {
        let value=try decode(#""version":3,"approvalRevision":0,"completionContract":{"schema":1,"steps":[{"name":"list_models","arguments":{}}]}"#)
        XCTAssertEqual(value.version,3); XCTAssertNotNil(value.completionContract); XCTAssertNil(value.readPlan)
    }
    func testRecoveredPendingCannotBroadenApprovedScope() throws {
        let fields = #""version":3,"approvalRevision":0,"completionContract":{"schema":1,"steps":[{"name":"list_models","arguments":{}}]}"#
        let invalid=raw(fields).replacingOccurrences(of:"\"pending\":null",with:#""pending":{"operationID":"12345678-1234-1234-1234-123456789abc:1","name":"get_app_info","arguments":{}}"#)
        XCTAssertThrowsError(try JSONDecoder().decode(LocalAgentSnapshot.self,from:Data(invalid.utf8)))
    }
    func testRecoveredPrematureAnswerCannotClaimCompletedChecklist() throws {
        let fields = #""version":3,"approvalRevision":0,"completionContract":{"schema":1,"steps":[{"name":"list_models","arguments":{}}]}"#
        let invalid=raw(fields).replacingOccurrences(of:"\"status\":\"ready\"",with:"\"status\":\"answered\"").replacingOccurrences(of:"\"answer\":null",with:"\"answer\":\"forged\"")
        XCTAssertThrowsError(try JSONDecoder().decode(LocalAgentSnapshot.self,from:Data(invalid.utf8)))
    }
}
