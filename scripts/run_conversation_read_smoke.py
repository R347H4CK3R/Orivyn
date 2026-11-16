#!/usr/bin/env python3
"""Real LocalReadTools dispatch and JS reducer; only AppModel history is a host scaffold."""
import argparse, hashlib, json, pathlib, runpy, subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--swiftc',required=True);p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
sources=runpy.run_path(str(root/'scripts/run_foundation_tests.py'))['SOURCES']+['JarvisEVO/Services/LocalReadTools.swift']
(out/'SOURCE-MANIFEST.json').write_text(json.dumps({n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in sources+['JarvisEVO/Resources/LocalAgentCore.js']},indent=2))
main=out/'Smoke.swift';main.write_text('''import Foundation
@MainActor final class AppModel {
 var conversations: [Conversation] = []
 var installedModels: [LocalModelDescriptor] = []
 var memories: [MemoryNote] = []
}
@main struct Smoke {
 @MainActor static func main() async throws {
  let model = AppModel(), id = UUID(uuidString:"abcdefab-1234-1234-1234-123456789abc")!
  model.conversations = [Conversation(id:id,messages:[ChatMessage(role:.user,content:"orchid " + String(repeating:"🦊",count:200))])]
  let search = try LocalReadTools.execute(name:"search_conversations",arguments:.object(["query":.string("orchid"),"limit":.integer(1)]),model:model,resultByteLimit:4096)
  let event = LocalAgentSnapshot.Event(operationID:"task:1",name:"search_conversations",arguments:.object([:]),outcome:"succeeded",result:search)
  let ids = LocalConversationRead.authorizedIDs(history:[event])
  let args:MCPJSONValue = .object(["id":.string(id.uuidString),"messageIndex":.integer(0),"offset":.integer(0)])
  let result = try LocalReadTools.execute(name:"read_conversation",arguments:args,model:model,resultByteLimit:4096,authorizedConversationIDs:ids)
  precondition(result.utf8.count <= 4096)
  func rejects(_ action:()throws->String) { do { _ = try action();fatalError("unauthorized read") } catch {} }
  rejects { try LocalReadTools.execute(name:"read_conversation",arguments:args,model:model) }
  rejects { try LocalReadTools.execute(name:"read_conversation",arguments:args,model:model,resultByteLimit:128,authorizedConversationIDs:ids) }
  model.conversations = []
  rejects { try LocalReadTools.execute(name:"read_conversation",arguments:args,model:model,authorizedConversationIDs:ids) }
  try Data(search.utf8).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  try Data(result.utf8).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
  model.memories = (0..<10_000).map { MemoryNote(content: $0 == 9999 ? "late orchid memory" : "unrelated note") }
  let memoryArguments: MCPJSONValue = .object(["query": .string("orchid"), "limit": .integer(1)])
  let memory = try await LocalReadTools.executeAsync(name: "search_memory", arguments: memoryArguments, model: model)
  let memoryObject = try MCPJSONValue.parse(Data(memory.utf8)).objectValue!
  precondition(memoryObject["searchedMemories"] == .integer(10_000))
  precondition(memoryObject["searchLimited"] == .bool(false))
  precondition(memory.contains("late orchid memory"))
  let canceled = Task { @MainActor in
   try await LocalReadTools.executeAsync(name: "search_memory", arguments: memoryArguments, model: model)
  }
  canceled.cancel()
  do { _ = try await canceled.value; fatalError("Canceled search returned successful evidence") }
  catch is CancellationError {}
  print("PASS actual async memory dispatcher: late 10,000th note found; cancellation rejected")
  print("PASS actual LocalReadTools search -> authorized page; denied absent provenance, tiny budget and deleted conversation")
 }
}
''')
cmd=[a.swiftc,'-swift-version','6','-parse-as-library','-module-cache-path',str(out/'module-cache'),*[str(root/n) for n in sources],str(main),'-o',str(out/'smoke')]
(out/'COMMAND.json').write_text(json.dumps(cmd))
with (out/'test.log').open('w') as log:
 subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
 subprocess.run([str(out/'smoke'),str(out/'search.json'),str(out/'page.json')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
 code="""const fs=require('node:fs'),assert=require('node:assert/strict'),a=require(process.argv[1]),search=fs.readFileSync(process.argv[2],'utf8'),page=fs.readFileSync(process.argv[3],'utf8'),id='12345678-1234-1234-1234-123456789abc';let s=a.create('Inspect orchid conversation',id);function call(name,args,result){s=a.acceptDecision(s,JSON.stringify({type:'tool',name,arguments:args}));s=a.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result}));}call('search_conversations',{query:'orchid',limit:1},search);call('read_conversation',{id:JSON.parse(search).matches[0].id,messageIndex:0,offset:0},page);assert.equal(JSON.parse(s).history[1].result,page);assert.equal(a.recover(s),s);assert.equal(JSON.parse(page).attachmentContentsIncluded,false);assert.ok(JSON.parse(page).next);console.log('PASS actual Swift search/page payloads through durable reducer and recovery');"""
 subprocess.run(['node','-e',code,str(root/'JarvisEVO/Resources/LocalAgentCore.js'),str(out/'search.json'),str(out/'page.json')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
(out/'STATUS.json').write_text(json.dumps({'passed':True,'actualDispatcher':True,'AppModelScaffold':True,'modelInference':False,'AppleVerified':False}));print((out/'test.log').read_text())
