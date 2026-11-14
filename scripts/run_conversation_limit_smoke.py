#!/usr/bin/env python3
"""Exact production conversation search branch and both JS consumers; not native iOS."""
import argparse, hashlib, json, pathlib, subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--swiftc',required=True);p.add_argument('--node',required=True);p.add_argument('--module-cache',required=True);p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
names=['MemoryNote','Conversation','ImageOCRResult','OCRLineEvidence','LocalConversationSearch','LocalSearchExcerpt','LocalAgentError','MCPTypes','MCPToolSchema'];sources=[];manifest=[]
for n in names:
 f=root/f'JarvisEVO/Core/{n}.swift';b=f.read_bytes();d=out/f.name;d.write_bytes(b);sources.append(str(d));manifest.append({'source':str(f.relative_to(root)),'sha256':hashlib.sha256(b).hexdigest()})
f=root/'JarvisEVO/Services/LocalReadTools.swift';raw=f.read_text();start=raw.index('        case "search_conversations":');end=raw.index('        case "search_memory":',start);branch=raw[start:end]
d=out/'Branch.swift';d.write_text('import Foundation\nstruct ModelScaffold {let conversations:[Conversation]}\nenum SearchBranch {static func execute(arguments:MCPJSONValue,model:ModelScaffold)throws->MCPJSONValue {let object:MCPJSONValue\nswitch "search_conversations" {\n'+branch+'default:throw LocalAgentError.invalidState\n}\nreturn object\n}}');sources.append(str(d));manifest.append({'source':str(f.relative_to(root)),'sha256':hashlib.sha256(raw.encode()).hexdigest(),'extractedBranchSHA256':hashlib.sha256(branch.encode()).hexdigest()})
d=out/'main.swift';d.write_text('''import Foundation
func check(_ ok:Bool,_ reason:String){if !ok {fatalError(reason)}}
func search(_ values:[Conversation],_ limit:Int64=1)throws->MCPJSONValue {try SearchBranch.execute(arguments:.object(["query":.string("orchid"),"limit":.integer(limit)]),model:ModelScaffold(conversations:values))}
let c=Conversation(title:"orchid")
let result=try search([c,c,c]);let r=result.objectValue!
check(r["totalMatchesInWindow"] == .integer(3),"Missing matching conversation count")
check(r["resultsLimited"] == .bool(true),"Omitted conversations not disclosed")
check(r["searchedConversations"] == .integer(3),"Wrong scan count")
let all=try search([c],10).objectValue!
check(all["resultsLimited"] == .bool(false),"Incorrect omission flag")
let empty=try search([]).objectValue!
check(empty["totalMatchesInWindow"] == .integer(0),"Wrong empty total")
let bounded=try search(Array(repeating:Conversation(title:"none"),count:500)+[c]).objectValue!
check(bounded["totalMatchesInWindow"] == .integer(0),"Scanned outside bounded window")
check(bounded["searchLimited"] == .bool(true),"Missing scan-bound flag")
try result.encoded(maximumBytes:20480).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
print("PASS exact conversation branch: match counts, omissions, complete and empty results, scan boundary")
''');sources.append(str(d))
for rel in ['JarvisEVO/Resources/VerifiedLocalPlan.js','JarvisEVO/Resources/LocalAgentCore.js','scripts/run_conversation_limit_smoke.py']:
 manifest.append({'source':rel,'sha256':hashlib.sha256((root/rel).read_bytes()).hexdigest()})
(out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2));cmd=[a.swiftc,'-swift-version','6','-module-cache-path',a.module_cache,*sources,'-o',str(out/'test')];(out/'COMMAND.json').write_text(json.dumps(cmd))
with (out/'test.log').open('w') as log:
 subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
 subprocess.run([str(out/'test'),str(out/'result.json')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
 code="""const fs=require('node:fs'),assert=require('node:assert/strict'),v=require(process.argv[1]),a=require(process.argv[2]),r=fs.readFileSync(process.argv[3],'utf8'),id='12345678-1234-1234-1234-123456789abc';let s=v.next(v.create(JSON.stringify({appInfo:false,installedModels:false,searchQuery:'orchid',memoryQuery:null}),id));s=v.record(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,resultJSON:r}));assert.deepEqual(JSON.parse(v.report(s)).evidence[0].result,JSON.parse(r));assert.equal(v.recover(s),s);let t=a.acceptDecision(a.create('Find orchid conversations',id),JSON.stringify({type:'tool',name:'search_conversations',arguments:{query:'orchid',limit:1}}));t=a.recordResult(t,JSON.stringify({operationID:JSON.parse(t).pending.operationID,result:r}));assert.equal(a.recover(t),t);console.log('PASS actual Swift conversation payload through both production reducers and recovery');"""
 subprocess.run([a.node,'-e',code,str(root/'JarvisEVO/Resources/VerifiedLocalPlan.js'),str(root/'JarvisEVO/Resources/LocalAgentCore.js'),str(out/'result.json')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
(out/'STATUS.json').write_text(json.dumps({'passed':True,'nativeVerified':False,'modelObedienceTested':False}));print((out/'test.log').read_text())
