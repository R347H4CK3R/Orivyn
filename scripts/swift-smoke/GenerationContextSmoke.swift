import Foundation
struct GenerationRequest: Sendable { let messages:[ChatMessage]; let systemPrompt:String; let maxTokens:Int; let temperature:Double; let conciseQwen3:Bool }
@MainActor protocol AIProvider { func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> }
@MainActor final class CapturingProvider: AIProvider {
 var request: GenerationRequest?
 func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { self.request=request; return AsyncThrowingStream { $0.yield("answer"); $0.finish() } }
}
@MainActor final class Store {
 var onSave:(() -> Void)?
 func save(_ conversation:Conversation) async throws { onSave?(); onSave=nil; await Task.yield() }
}
enum LocalHeavyWorkError:Error { case busy }
enum ProviderError:Error { case emptyResponse }
@MainActor final class VoiceTurnTicket { var id=UUID() }
struct MemoryNote:Sendable,Codable {}
@MainActor enum MemoryContextBuilder {
 struct Selection { let totalCount=0; let includedCount=0; let scannedCount=0; let truncated=false; let text="" }
 static var lastBudget=0
 static func build(notes:[MemoryNote],query:String,maximumBytes:Int)->Selection { lastBudget=maximumBytes; return Selection() }
}
struct Behavior { let prompt="" }; struct Workspace { let behavior=Behavior() }
@MainActor final class Model {
 var selectedProviderID="remote"; var isInferenceAdmissionBlocked=false; var generationID:UUID?; var isGenerating=false; var generatingConversationID:UUID?; var isSavingSubmittedTurn=false; var attachmentImportEpoch=UUID()
 var generationTask:Task<Result<String,any Error>,Never>?; var activeVoiceTurn:VoiceTurnTicket?; var conversations:[Conversation]=[]; let store=Store(); var memories:[MemoryNote]=[]; var lastMemoryContextSummary:String?; let workspace=Workspace(); var conciseQwen3=true
 var selectedConversationID:UUID?; var draft=""; var pendingAttachments:[ChatAttachment]=[]; var attachmentImportJobs:[UUID:Int]=[:]; var statusMessage:String?; var errorMessage:String?
 func validateGeneration(_ ticket:VoiceTurnTicket?) throws { try Task.checkCancellation() }
 func persist(_ id:UUID) async throws { try await store.save(conversations.first{$0.id==id}!) }
 func updateMessage(conversationID:UUID,messageID:UUID,update:(inout ChatMessage)->Void) { let i=conversations.firstIndex{$0.id==conversationID}!; let j=conversations[i].messages.firstIndex{$0.id==messageID}!; update(&conversations[i].messages[j]) }
 func applyingOwnedComposerUpdate(_ update:()->Void) {update()}; func requestAttachmentCleanup(){}; func report(_ error:Error){errorMessage=String(describing:error)}
 // PRODUCTION_METHOD
 func run(actual:String,picker:String,switchDuringSave:String?) async -> Bool {
  selectedProviderID=picker; let provider=CapturingProvider(); let answer=ChatMessage(role:.assistant,content:"",state:.streaming)
  let chat=Conversation(messages:[ChatMessage(role:.user,content:"Which model is answering?"),answer]); conversations=[chat]; selectedConversationID=chat.id
  store.onSave={ [weak self] in if let next=switchDuringSave {self?.selectedProviderID=next} }
  let task = startGeneration(conversationID:chat.id,assistantID:answer.id,provider:provider/* PROVIDER_ID */)
  let result=await task.value
  guard case .success = result, let request=provider.request else { print("ERROR no generation"); return false }
  let expected="Selected provider: \(actual)."
  let correct=request.systemPrompt.contains(expected) && MemoryContextBuilder.lastBudget == (actual == "remote" ? 1024 : 512)
  print("\(correct ? "PASS" : "FAIL") actual=\(actual) picker=\(picker) later=\(switchDuringSave ?? "none") budget=\(MemoryContextBuilder.lastBudget) prompt=\(request.systemPrompt.contains(expected))")
  return correct
 }
}
@main struct Main {
 @MainActor static func main() async {
  var failures=0
  for item:(String,String,String?) in [("qwen-local","remote",nil),("qwen-local","apple-system",nil),("remote","remote","qwen-local"),("qwen-local","qwen-local","remote"),("remote","remote",nil),("apple-system","apple-system",nil)] {
   if !(await Model().run(actual:item.0,picker:item.1,switchDuringSave:item.2)) {failures += 1}
  }
  print("failures=\(failures)/6"); exit(failures == 0 ? 0 : 1)
 }
}
