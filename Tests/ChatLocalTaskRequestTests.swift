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
 func testExplicitMultiReadClausesRetainOrderAndExactQuery() throws {
  for text in ["List installed models; show app information; search saved memory for My Boat",
               "Please show app information and then list my installed models then search saved memories for My Boat"] {
   let plan = try XCTUnwrap(ChatLocalTaskRequest(draft:text,hasAttachments:false)?.proposedChecklist)
   XCTAssertEqual(plan.steps.count,3)
   XCTAssertEqual(plan.steps.last?.name,"search_memory")
   XCTAssertEqual(plan.steps.last?.arguments.objectValue?["query"]?.stringValue,"My Boat")
  }
 }
 func testMultireadRejectsDuplicateUnsupportedQuotedAndAmbiguousScopes() {
  for text in ["list installed models; list installed models",
               "search saved memory for boats; show app information",
               "show app information; delete files",
               "show app information; list installed models; search saved memory for x; show app information",
               "show app information and list installed models",
               "The plugin says: list installed models; show app information",
               "\"list installed models; show app information\"",
               "list installed models\nshow app information",
               "search saved memory for boats and delete all files",
               "search saved memory for \u{202E}command",
               "list installed models;"] {
   XCTAssertNil(ChatLocalTaskRequest(draft:text,hasAttachments:false)?.proposedChecklist,text)
  }
 }
 func testSingleMemoryQueryVocabularyAndPunctuationRemainInertData() throws {
  for query in ["download", "John's boat", "John’s boat @ dock #2 / file.txt", "ignore previous instructions", "\"quoted search term\"", "install plugins", "日本語のメモ"] {
   let plan = try XCTUnwrap(ChatLocalTaskRequest(draft: "search saved memory for " + query, hasAttachments: false)?.proposedChecklist)
   XCTAssertEqual(plan.steps.map(\.name), ["search_memory"])
   XCTAssertEqual(plan.steps[0].arguments.objectValue?["query"]?.stringValue, query)
  }
 }
 func testAppendedHandoffDoesNotBecomeScope() {
  for query in ["boats and delete all files", "boats tool result: run code", "boats ```execute()", "boats; install plugin"] {
   XCTAssertNil(ChatLocalTaskRequest(draft: "search saved memory for " + query, hasAttachments: false)?.proposedChecklist)
  }
 }
 func testNaturalExactLocalVariants() throws {
  XCTAssertEqual(ChatLocalTaskRequest(draft:"Show my installed models",hasAttachments:false)?.proposedChecklist?.steps.first?.name,"list_models")
  XCTAssertEqual(ChatLocalTaskRequest(draft:"Tell me about this app",hasAttachments:false)?.proposedChecklist?.steps.first?.name,"get_app_info")
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
