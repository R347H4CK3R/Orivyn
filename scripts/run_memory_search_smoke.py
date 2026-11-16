#!/usr/bin/env python3
"""Execute exact saved-memory tool branch and production JS reducer. Not iOS UI proof."""
import argparse, hashlib, json, os, pathlib, subprocess

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',required=True);p.add_argument('--node',required=True);p.add_argument('--output',required=True,type=pathlib.Path);p.add_argument('--module-cache',required=True);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 names=['MemorySearch','MemoryNote','LocalSearchExcerpt','LocalAgentError','MCPTypes','MCPToolSchema','LocalToolResultBudget'];manifest=[];sources=[]
 for name in names:
  f=root/f'JarvisEVO/Core/{name}.swift';data=f.read_bytes();dest=out/f.name;dest.write_bytes(data);sources.append(str(dest));manifest.append({'source':str(f.relative_to(root)),'sha256':hashlib.sha256(data).hexdigest()})
 f=root/'JarvisEVO/Services/LocalReadTools.swift';raw=f.read_text();start=raw.index('        case "search_memory":');end=raw.index('\n        default:',start+1);branch=raw[start:end]
 (out/'ExactBranch.swift.txt').write_text(branch);manifest.append({'source':str(f.relative_to(root)),'sha256':hashlib.sha256(raw.encode()).hexdigest(),'extractedBranchSHA256':hashlib.sha256(branch.encode()).hexdigest()})
 helper = raw[raw.index('    nonisolated private static func memoryResult'):raw.rfind('}')].replace('nonisolated private static', 'static')
 (out/'MemoryBranch.swift').write_text('import Foundation\nstruct ModelScaffold { let memories: [MemoryNote] }\nenum MemoryBranch { static func execute(arguments: MCPJSONValue, model: ModelScaffold) throws -> MCPJSONValue { let object: MCPJSONValue\nswitch "search_memory" {\n'+branch+'\ndefault: throw LocalAgentError.invalidState\n}\nreturn object\n}\n'+helper+'}\n');sources.append(str(out/'MemoryBranch.swift'))
 (out/'main.swift').write_text('''import Foundation
func check(_ ok: Bool, _ reason: String) { if !ok { fatalError(reason) } }
func search(_ query: String, _ notes: [MemoryNote], _ limit: Int64 = 3) throws -> MCPJSONValue {
 try MemoryBranch.execute(arguments:.object(["query":.string(query),"limit":.integer(limit)]),model:ModelScaffold(memories:notes))
}
let result = try search("coffee", [MemoryNote(content:"Coffee preference: decaf only"),MemoryNote(content:"Unrelated note")])
let object = result.objectValue!
guard case .array(let matches) = object["memories"] else { fatalError("No memories") }
check(matches.count == 1, "Expected one match")
check(matches[0].objectValue?["excerpt"] == .string("Coffee preference: decaf only"), "Wrong evidence")
check(object["searchedMemories"] == .integer(2), "Wrong count")
let capped = try search("needle", (0..<5).map { _ in MemoryNote(content:"needle") }, 2)
check(capped.objectValue?["totalMatchesInWindow"] == .integer(5),"Missing bounded match total")
check(capped.objectValue?["resultsLimited"] == .bool(true),"Silently omitted matching memories")
check(result.objectValue?["resultsLimited"] == .bool(false),"Incorrect truncation flag")
let bounded = try search("needle", (0..<500).map { _ in MemoryNote(content:"unrelated") } + [MemoryNote(content:"needle")])
check(bounded.objectValue?["searchLimited"] == .bool(false),"Full search incorrectly limited")
check(bounded.objectValue?["searchedMemories"] == .integer(501),"Search did not scan full library")
check(bounded.objectValue?["memories"] != .array([]),"Late matching memory omitted")
let unicode = try search("cafe", [MemoryNote(content:"Café choice")])
check(unicode.objectValue?["memories"] != .array([]),"Diacritic matching failed")
for arguments: MCPJSONValue in [.object(["query":.string("x"),"limit":.integer(11)]),.object(["query":.string("x"),"limit":.integer(1),"extra":.bool(true)]),.object(["query":.string(" "),"limit":.integer(1)])] {
 do { _ = try MemoryBranch.execute(arguments:arguments,model:ModelScaffold(memories:[]));fatalError("Invalid args accepted") } catch LocalAgentError.invalidState {}
}
let encoded = try LocalToolResultBudget.encode(result,collection:"memories",maximumBytes:4096)
try encoded.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
print("PASS exact production search_memory: matching, UTF-8 result budget, scan bound, diacritics, invalid arguments")
''');sources.append(str(out/'main.swift'))
 for relative in ['JarvisEVO/Resources/LocalAgentCore.js','JarvisEVO/Resources/VerifiedLocalPlan.js','JarvisEVO/Resources/LocalAgentDecision.gbnf','scripts/run_memory_search_smoke.py']:
  data=(root/relative).read_bytes();manifest.append({'source':relative,'sha256':hashlib.sha256(data).hexdigest()})
 cmd=[a.swiftc,'-swift-version','6','-module-cache-path',a.module_cache,*sources,'-o',str(out/'memory-smoke')]
 (out/'COMMAND.json').write_text(json.dumps(cmd));(out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2))
 with (out/'test.log').open('w') as log:
  subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
  subprocess.run([str(out/'memory-smoke'),str(out/'actual-tool-result.json')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
  script='''const fs=require('node:fs'),a=require(process.argv[1]),assert=require('node:assert/strict');let s=a.create('Find my saved coffee preference','12345678-1234-1234-1234-123456789abc');s=a.acceptDecision(s,JSON.stringify({type:'tool',name:'search_memory',arguments:{query:'coffee',limit:3}}));const result=fs.readFileSync(process.argv[2],'utf8');s=a.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result}));assert.match(a.prompt(s),/decaf only/);assert.equal(a.recover(s),s);fs.writeFileSync(process.argv[3],s);console.log('PASS actual Swift memory result accepted by production JS and survives recovery (model-generated answer not claimed)');'''
  subprocess.run([a.node,'-e',script,str(root/'JarvisEVO/Resources/LocalAgentCore.js'),str(out/'actual-tool-result.json'),str(out/'agent-state.json')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
  verified="""const fs=require('node:fs'),a=require(process.argv[1]),assert=require('node:assert/strict');let s=a.create(JSON.stringify({appInfo:false,installedModels:false,searchQuery:null,memoryQuery:'coffee'}),'12345678-1234-1234-1234-123456789abc');s=a.next(s);const result=fs.readFileSync(process.argv[2],'utf8');s=a.record(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,resultJSON:result}));assert.deepEqual(JSON.parse(a.report(s)).evidence[0].result,JSON.parse(result));assert.equal(a.recover(s),s);console.log('PASS exact Swift memory payload accepted by verified-plan report/recovery');"""
  subprocess.run([a.node,'-e',verified,str(root/'JarvisEVO/Resources/VerifiedLocalPlan.js'),str(out/'actual-tool-result.json')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
 (out/'STATUS.json').write_text(json.dumps({'testExit':0,'nativeVerified':False,'exactBranchOnly':True,'modelInferenceTested':False}))
 print((out/'test.log').read_text())
if __name__=='__main__':main()
