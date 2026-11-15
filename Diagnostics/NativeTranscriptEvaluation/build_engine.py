"""Compile exact production LlamaEngine on Linux with real Swift Crypto and llama."""
import hashlib,json,os,pathlib,runpy,shutil,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[2]
out=pathlib.Path(sys.argv[1]).resolve();out.mkdir(parents=True,exist_ok=True)
runtime=pathlib.Path(os.environ['LLAMA_SOURCE'])/'build/bin'
headers=pathlib.Path(os.environ['LLAMA_SOURCE'])/'include'
base=runpy.run_path(str(root/'scripts/run_llama_engine_smoke.py'))['SOURCES']
extra=['LocalReviewedSearch','LocalConversationSearch','LocalSearchExcerpt','AttachmentTextSearch','LocalToolResultBudget','LocalReadPlan','LocalReadWorkflowPolicy','LocalConversationRead','LocalAgentSnapshot','LocalCalculationEvidence','NativeToolTranscript','NativeToolResponseAdapter']
sources=list(dict.fromkeys([p for p in base if not p.endswith('LlamaEngineSmoke.swift')]+['JarvisEVO/Core/'+n+'.swift' for n in extra]+['Diagnostics/NativeTranscriptEvaluation/NativeEngineCLI.swift']))
dest=out/'Sources/EngineCLI';dest.mkdir(parents=True,exist_ok=True)
manifest=[]
for name in sources:
 data=(root/name).read_bytes();(dest/pathlib.Path(name).name).write_bytes(data)
 manifest.append({'source':name,'sha256':hashlib.sha256(data).hexdigest()})
module=out/'Sources/llama';module.mkdir(parents=True,exist_ok=True)
(module/'module.modulemap').write_text('module llama [system] { header "'+str(headers/'llama.h')+'" link "llama" link "ggml" export * }\n')
(out/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package=Package(name:"EngineProof",dependencies:[.package(url:"https://github.com/apple/swift-crypto.git",revision:"e8d6eba1fef23ae5b359c46b03f7d94be2f41fed")],targets:[
.systemLibrary(name:"llama"),
.executableTarget(name:"EngineCLI",dependencies:["llama",.product(name:"Crypto",package:"swift-crypto")],swiftSettings:[.define("ORIVYN_NATIVE_TRANSCRIPT"),.unsafeFlags(["-Xcc","-I'''+str(pathlib.Path(os.environ['LLAMA_SOURCE'])/'ggml/include')+'''"])],linkerSettings:[.unsafeFlags(["-L","'''+str(runtime)+'''","-Xlinker","-rpath","-Xlinker","'''+str(runtime)+'''"])])])
''')
resource='JarvisEVO/Resources/LocalAgentDecision.gbnf'
data=(root/resource).read_bytes()
(out/'LocalAgentDecision.gbnf').write_bytes(data)
manifest.append({'source':resource,'sha256':hashlib.sha256(data).hexdigest()})
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2))
env={**os.environ,'LD_LIBRARY_PATH':str(runtime)}
with (out/'compile.log').open('w') as log:
 p=subprocess.run(['swift','build','--jobs','2','--package-path',str(out)],env=env,stdout=log,stderr=subprocess.STDOUT)
if p.returncode:
 print((out/'compile.log').read_text());raise SystemExit(p.returncode)
binary=subprocess.check_output(['swift','build','--package-path',str(out),'--show-bin-path'],text=True).strip()
shutil.copy2(pathlib.Path(binary)/'EngineCLI',out/'native-engine-cli')
print('Compiled exact production engine with ORIVYN_NATIVE_TRANSCRIPT; no app route enabled')
