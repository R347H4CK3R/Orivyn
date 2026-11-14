import XCTest
@testable import JarvisEVO

final class LocalAgentSnapshotEvidenceTests: XCTestCase {
    func testDecodedEvidenceDoesNotDependOnModelAnswer() throws {
        let raw = #"{"history":[{"operationID":"test:1","name":"calculate","arguments":{"expression":"(12 + 8) / 4"},"outcome":"succeeded","result":"{\"expression\":\"(12 + 8) / 4\",\"result\":\"5\",\"approximate\":true,\"engine\":\"local-arithmetic\"}"}],"id":"test","goal":"Calculate (12 + 8) / 4","status":"answered","revision":3,"steps":1,"pending":null,"answer":"It is 14","error":null}"#
        let snapshot = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(raw.utf8))
        XCTAssertEqual(snapshot.answer, "It is 14", "Do not rewrite or silently endorse model prose")
        let event = try XCTUnwrap(snapshot.history.first)
        XCTAssertEqual(event.calculationEvidence(goal: snapshot.goal)?.result, "5")
        XCTAssertNil(event.calculationEvidence(goal: "Calculate 12 + 8 / 4"))
    }
    func testOnlySuccessfulCalculatorEventsQualify() throws {
        let result = try LocalCalculatorTool.execute(arguments: .object(["expression": .string("2+3")]), requestedGoal: "Calculate 2+3")
        for (name,outcome) in [("get_app_info","succeeded"),("calculate","failed"),("calculate","interrupted")] {
            let event = LocalAgentSnapshot.Event(operationID: "test:1", name: name, arguments: .object(["expression": .string("2+3")]), outcome: outcome, result: result)
            XCTAssertNil(event.calculationEvidence(goal: "Calculate 2+3"))
        }
    }
}
