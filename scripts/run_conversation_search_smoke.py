#!/usr/bin/env python3
"""Execute exact search_conversations production switch branch with actual Foundation helpers.
Only the AppModel conversation input is a scaffold; other tool branches are excluded.
"""
import argparse, hashlib, json, os, pathlib, subprocess

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swift',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 src=out/'Sources/JarvisEVO';test=out/'Tests/JarvisEVOTests';src.mkdir(parents=True);test.mkdir(parents=True)
 names=['Conversation','MemoryNote','ImageOCRResult','OCRLineEvidence','LocalSearchExcerpt','LocalConversationSearch','LocalAgentError','MCPTypes','MCPToolSchema']
 manifest=[]
 for name in names:
  path=root/f'JarvisEVO/Core/{name}.swift';data=path.read_bytes();(src/path.name).write_bytes(data);manifest.append({'source':str(path.relative_to(root)),'sha256':hashlib.sha256(data).hexdigest()})
 path=root/'JarvisEVO/Services/LocalReadTools.swift';raw=path.read_text();start=raw.index('        case "search_conversations":');end=raw.index('        case "search_memory":',start);branch=raw[start:end]
 (out/'ExactBranch.swift.txt').write_text(branch)
 (src/'SearchBranch.swift').write_text('import Foundation\nstruct ModelScaffold { let conversations: [Conversation] }\nenum SearchBranch { static func execute(arguments: MCPJSONValue, model: ModelScaffold) throws -> MCPJSONValue { let object: MCPJSONValue\n switch "search_conversations" {\n'+branch+'default: throw LocalAgentError.invalidState\n}\nreturn object\n}}\n')
 manifest.append({'source':str(path.relative_to(root)),'sha256':hashlib.sha256(raw.encode()).hexdigest(),'extractedBranchSHA256':hashlib.sha256(branch.encode()).hexdigest(),'branchExact':branch in raw})
 (test/'SearchBranchTests.swift').write_text('''import XCTest
@testable import JarvisEVO
final class SearchBranchTests: XCTestCase {
 func testActualToolBranchFindsAttachmentEvidenceAndEncodesSchema() throws {
  let a = ChatAttachment(name: "fixture.pdf", relativePath: "private-path", mediaType: "application/pdf", byteCount: 1, extractedText: "ORCHID is in this stored document")
  let c = Conversation(title: "Unrelated", messages: [ChatMessage(role: .user, content: "Read it", attachments: [a])])
  let result = try SearchBranch.execute(arguments: .object(["query":.string("orchid"),"limit":.integer(10)]), model: ModelScaffold(conversations:[c]))
  let object = try XCTUnwrap(result.objectValue)
  guard case .array(let matches) = object["matches"] else { return XCTFail("Missing matches") }
  XCTAssertEqual(matches.count,1)
  XCTAssertEqual(matches[0].objectValue?["evidenceSource"],.string("attachment_text"))
  XCTAssertEqual(matches[0].objectValue?["excerpt"],.string("ORCHID is in this stored document"))
  XCTAssertEqual(object["searchedConversations"],.integer(1)); XCTAssertEqual(object["searchLimited"],.bool(false))
  let encoded = try result.encoded(maximumBytes:20480)
  XCTAssertFalse(String(decoding:encoded,as:UTF8.self).contains("private-path"))
  if let path = ProcessInfo.processInfo.environment["SEARCH_RESULT_PATH"] { try encoded.write(to: URL(fileURLWithPath:path)) }
 }
 func testActualToolBranchRejectsExtraArguments() {
  XCTAssertThrowsError(try SearchBranch.execute(arguments:.object(["query":.string("x"),"limit":.integer(1),"extra":.bool(true)]),model:ModelScaffold(conversations:[])))
 }
}
''')
 (out/'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name:"ReadSearchProof",targets:[.target(name:"JarvisEVO"),.testTarget(name:"JarvisEVOTests",dependencies:["JarvisEVO"])])\n')
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2))
 env=dict(os.environ,SEARCH_RESULT_PATH=str(out/'actual-tool-result.json'),CLANG_MODULE_CACHE_PATH=str(out/'.clang-cache'),SWIFTPM_MODULECACHE_OVERRIDE=str(out/'.module-cache'))
 cmd=[a.swift,'test','--jobs','2','--package-path',str(out),'--cache-path',str(out/'.cache'),'--config-path',str(out/'.config'),'--security-path',str(out/'.security')]
 (out/'COMMAND.json').write_text(json.dumps(cmd))
 with (out/'test.log').open('w') as log:r=subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180)
 (out/'STATUS.json').write_text(json.dumps({'testExit':r.returncode,'nativeVerified':False,'exactBranchOnly':True}))
 print((out/'test.log').read_text());return r.returncode
if __name__=='__main__':raise SystemExit(main())
