import XCTest
@testable import JarvisEVO
final class ChatLocalTaskRequestTests: XCTestCase {
 func testExactRequestsProduceOnlySingleReadOnlyOperation() throws {
  let models = try XCTUnwrap(ChatLocalTaskRequest(draft:"Please list installed models",hasAttachments:false)!.proposedChecklist)
  XCTAssertEqual(models.steps.map(\.name), ["list_models"])
  let info = try XCTUnwrap(ChatLocalTaskRequest(draft:"Show app information",hasAttachments:false)!.proposedChecklist)
  XCTAssertEqual(info.steps.map(\.name), ["get_app_info"])
  let memory = try XCTUnwrap(ChatLocalTaskRequest(draft:"Search saved memory for My Boat",hasAttachments:false)!.proposedChecklist)
  XCTAssertEqual(memory.steps.map(\.name), ["search_memory"])
  XCTAssertEqual(memory.steps[0].arguments.objectValue?["query"]?.stringValue,"My Boat")
  XCTAssertEqual(memory.steps[0].arguments.objectValue?["limit"]?.integerValue,3)
 }
 func testAmbiguousOrCompoundRequestsRemainOrdinaryChat() {
  for input in ["List installed models and delete one", "How do I list installed models?", "Do not list installed models", "Search saved memory", "Search saved memory for ", "Search saved memory for " + String(repeating:"x",count:257), "Read saved conversations", "Send an email"] {
   XCTAssertNil(ChatLocalTaskRequest(draft:input,hasAttachments:false)!.proposedChecklist)
  }
 }
 func testCopiesTypedGoalWithoutChangingIt() {
  XCTAssertEqual(ChatLocalTaskRequest(draft: "Search saved memory for boats", hasAttachments: false)?.goal, "Search saved memory for boats")
 }
 func testRejectsEmptyOversizedControlsAndAttachments() {
  for text in ["", " \n ", String(repeating:"a",count:513), "hello\u{0}world", "hello\u{1}world"] {
   XCTAssertNil(ChatLocalTaskRequest(draft:text,hasAttachments:false))
  }
  XCTAssertNil(ChatLocalTaskRequest(draft:"Read this file",hasAttachments:true))
 }
 func testUTF8LimitNotCharacterCount() {
  XCTAssertNotNil(ChatLocalTaskRequest(draft:String(repeating:"é",count:256),hasAttachments:false))
  XCTAssertNil(ChatLocalTaskRequest(draft:String(repeating:"é",count:257),hasAttachments:false))
 }
 func testOnlyDirectSupportedRequestsSuggestReview() {
  for text in ["Search saved memory for boats", "Please search saved conversations for trip", "List installed models", "Show app information"] {
   XCTAssertTrue(ChatLocalTaskRequest(draft:text,hasAttachments:false)!.suggestsLocalReview)
  }
  for text in ["How do I search saved memory?", "Do not list installed models", "\"List installed models\"", "Send email", "Delete all memories", "Summarize this web page"] {
   XCTAssertFalse(ChatLocalTaskRequest(draft:text,hasAttachments:false)!.suggestsLocalReview)
  }
 }
}
