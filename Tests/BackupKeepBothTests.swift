import Foundation
import XCTest
@testable import JarvisEVO

final class BackupKeepBothTests: XCTestCase {
 func testPreservesBothVersionsAndRejectsUnsafeBatch() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let store=try SQLiteConversationStore(url:root.appendingPathComponent("history.sqlite"))
  let local=Conversation(title:"Original",messages:[ChatMessage(role:.user,content:"Local message")])
  try await store.save(local)
  var incoming=local;incoming.messages[0].content="Remote edit"
  let data=try JSONEncoder().encode(ConversationBackup(conversations:[incoming],memories:[]))
  _=try await store.importData(data,policy:.keepBoth)
  let all=try await store.list(includeArchived:true)
  XCTAssertTrue(all.count == 2,"Conflicting versions must both survive")
  XCTAssertTrue(all.first(where:{$0.id == local.id}) == local,"Local original changed")
  XCTAssertTrue(all.contains(where:{$0.id != local.id && $0.messages == incoming.messages}),"Incoming content missing")
  let original=try await store.load(id:local.id)
  XCTAssertTrue(original == local)
  _=try await store.importData(data,policy:.keepBoth)
  let repeated=try await store.list(includeArchived:true)
  XCTAssertTrue(repeated.count == 3,"Repeated conflict copy behavior must match warning")
  let identical=try JSONEncoder().encode(ConversationBackup(conversations:[local],memories:[]))
  let same=try await store.importData(identical,policy:.keepBoth)
  XCTAssertTrue(same.writtenConversations == 0 && same.skippedConversations == 1)
  let note=MemoryNote(content:"Local note");try await store.saveMemory(note)
  var changedNote=note;changedNote.content="Incoming note"
  let memoryData=try JSONEncoder().encode(ConversationBackup(conversations:[],memories:[changedNote]))
  let summary=try await store.importData(memoryData,policy:.keepBoth)
  let notes=try await store.memories()
  XCTAssertTrue(summary.copiedMemories == 1 && notes.count == 2 && notes.contains(note))
  XCTAssertTrue(notes.contains(where:{$0.id != note.id && $0.content == changedNote.content}))
  let before=try await store.list(includeArchived:true)
  let preserved=try await store.importData(data,policy:.preserveLocal)
  XCTAssertTrue(preserved.writtenConversations == 0)
  let after=try await store.list(includeArchived:true);XCTAssertTrue(after == before)
  _=try await store.importData(data,policy:.replaceMatching)
  let replaced=try await store.load(id:local.id);XCTAssertTrue(replaced == incoming)
  let newConversation=Conversation(title:"New",messages:[ChatMessage(role:.user,content:"New record")])
  let mixed=try JSONEncoder().encode(ConversationBackup(conversations:[incoming,newConversation],memories:[note]))
  let mixedSummary=try await store.importData(mixed,policy:.keepBoth)
  XCTAssertTrue(mixedSummary.writtenConversations == 1 && mixedSummary.skippedConversations == 1 && mixedSummary.skippedMemories == 1)
  let imageID=UUID()
  let image=ChatAttachment(id:imageID,name:"Original",relativePath:imageID.uuidString+".png",mediaType:"image/png",byteCount:10)
  let imageConversation=Conversation(messages:[ChatMessage(role:.user,content:"Image local",attachments:[image])])
  try await store.save(imageConversation)
  var alteredImage=imageConversation;alteredImage.messages[0].content="Incoming image";alteredImage.messages[0].attachments[0].byteCount=11
  let invalid=try JSONEncoder().encode(ConversationBackup(conversations:[newConversation,alteredImage],memories:[MemoryNote(content:"Must not commit")]))
  let beforeInvalid=try await store.exportData()
  do { _=try await store.importData(invalid,policy:.keepBoth);fatalError("Conflicting image identity accepted") } catch ConversationError.unsafeAttachment {}
  let validImage=try await store.load(id:imageConversation.id);XCTAssertTrue(validImage == imageConversation)
  let afterNotes=try await store.memories();XCTAssertTrue(!afterNotes.contains(where:{$0.content == "Must not commit"}))
  var sharedImage=imageConversation;sharedImage.messages[0].content="Changed text, same original reference"
  let sharedData=try JSONEncoder().encode(ConversationBackup(conversations:[sharedImage],memories:[]))
  _=try await store.importData(sharedData,policy:.keepBoth)
  let imageCopies=try await store.list(includeArchived:true).filter{ $0.messages.first?.attachments.first?.id == imageID }
  XCTAssertTrue(imageCopies.count == 2 && imageCopies.allSatisfy{$0.messages[0].attachments[0] == image})
  let canceled=Task { withUnsafeCurrentTask { $0?.cancel() };return try await store.importData(data,policy:.keepBoth) }
  do {_=try await canceled.value;fatalError("Canceled import committed")} catch is CancellationError {}
  let streaming=Conversation(title:"Interrupted",messages:[ChatMessage(role:.assistant,content:"Partial",state:.streaming)])
  try await store.save(streaming)
  let streamingData=try JSONEncoder().encode(ConversationBackup(conversations:[streaming],memories:[]))
  let streamResult=try await store.importData(streamingData,policy:.keepBoth)
  XCTAssertTrue(streamResult.copiedConversations == 1,"Raw streaming vs reopened interrupted differs explicitly")
  let reopened=try await store.load(id:streaming.id)
  XCTAssertTrue(reopened?.messages.first?.state == .interrupted)
  let final=try await store.list(includeArchived:true)
  XCTAssertTrue(Set(final.map(\.id)).count == final.count)
  _=beforeInvalid
  print("PASS 12 checks: conflict preservation, repeat behavior, identical skip, memory copies, preserveLocal, replacement, mixed add/skip, unsafe image rollback, original preservation, shared attachment binding, cancellation, interrupted stream preservation")
 }
}
