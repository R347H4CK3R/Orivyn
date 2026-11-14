#!/usr/bin/env python3
"""Compile/run exact production Swift LlamaEngine with explicit matching Linux runtime/headers.
No downloads, no model substitute, no Apple framework/device verification.
"""
import argparse,hashlib,json,os,pathlib,subprocess,shutil,time,runpy
SOURCES=['JarvisEVO/Core/NativeReadProposal.swift','JarvisEVO/Core/LocalCalculatorRequest.swift','JarvisEVO/Core/LocalCalculator.swift','JarvisEVO/Core/LocalCalculatorTool.swift','JarvisEVO/Core/MCPTypes.swift','JarvisEVO/Core/MCPToolSchema.swift','JarvisEVO/Providers/Local/LlamaEngine.swift','JarvisEVO/Providers/Local/LocalPromptBuilder.swift',
 'JarvisEVO/Providers/Local/UTF8TokenAccumulator.swift','JarvisEVO/Providers/Local/LocalModelCatalog.swift',
 'JarvisEVO/Providers/Local/LocalModelCatalogData.swift','JarvisEVO/Core/AIProvider.swift',
 'JarvisEVO/Core/MemoryContextBuilder.swift','JarvisEVO/Core/Conversation.swift','JarvisEVO/Core/MemoryNote.swift','JarvisEVO/Core/ImageOCRResult.swift',
 'JarvisEVO/Core/OCRLineEvidence.swift','JarvisEVO/Core/ProviderError.swift','JarvisEVO/Core/LocalHeavyWork.swift',
 'JarvisEVO/Core/LocalAgentGrammar.swift','JarvisEVO/Core/LocalAgentError.swift','scripts/swift-smoke/LlamaEngineSmoke.swift']
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--scenario',choices=['engine','qwen-mode','calculator-agent','conversation-agent'],default='engine')
 for n in ['swiftc','runtime','headers','model','output']:p.add_argument('--'+n,required=True,type=pathlib.Path)
 p.add_argument('--run-timeout',type=int,default=180)
 a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);manifest=[];files=[]
 sources = list(SOURCES)
 if a.scenario != 'engine':
  driver = {'qwen-mode':'QwenModeSmoke.swift','calculator-agent':'CalculatorAgentSmoke.swift','conversation-agent':'ConversationAgentSmoke.swift'}[a.scenario]
  sources = [n for n in sources if n != 'scripts/swift-smoke/LlamaEngineSmoke.swift'] + ['scripts/swift-smoke/'+driver]
 if a.scenario in ['calculator-agent','conversation-agent']: sources += ['JarvisEVO/Services/LocalAgentStore.swift','JarvisEVO/Core/LocalAgentSnapshot.swift','JarvisEVO/Core/LocalCalculationEvidence.swift']
 if a.scenario == 'conversation-agent':
  sources = list(dict.fromkeys(sources + runpy.run_path(str(root/'scripts/run_foundation_tests.py'))['SOURCES'] + ['JarvisEVO/Services/LocalReadTools.swift']))
 for n in sources:
  b=(root/n).read_bytes();dest=out/pathlib.Path(n).name;dest.write_bytes(b);files.append(str(dest));manifest.append({'source':n,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)})
 # Bundle.main on this Linux command-line host finds resources beside the executable.
 # Copy the exact shipped grammar, without claiming Apple bundle packaging validation.
 resource='JarvisEVO/Resources/LocalAgentDecision.gbnf'
 b=(root/resource).read_bytes();(out/'LocalAgentDecision.gbnf').write_bytes(b)
 manifest.append({'source':resource,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)})
 if a.scenario in ['calculator-agent','conversation-agent']:
  for resource in ['JarvisEVO/Resources/LocalAgentCore.js','scripts/swift-smoke/CalculatorAgentCore.cjs']:
   b=(root/resource).read_bytes();(out/pathlib.Path(resource).name).write_bytes(b)
   manifest.append({'source':resource,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)})
 module=out/'llama';module.mkdir();shutil.copytree(a.headers,module/'include')
 (module/'module.modulemap').write_text('module llama [system] { header "include/llama.h" link "llama" export * }\n')
 for f in sorted((module/'include').glob('*.h')):
  b=f.read_bytes();manifest.append({'source':'external-b9049/'+f.name,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)})
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 def digest(path):
  h=hashlib.sha256()
  with path.open('rb') as f:
   for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
  return {'path':str(path.resolve()),'bytes':path.stat().st_size,'sha256':h.hexdigest()}
 runtime=a.runtime.resolve()
 (out/'RUNTIME-MODEL-MANIFEST.json').write_text(json.dumps({'model':digest(a.model),'additionalModels':[digest(a.model.parent/n) for n in ['Qwen3-0.6B-Q8_0.gguf','Qwen3-1.7B-Q8_0.gguf']] if a.scenario == 'qwen-mode' else [],'libraries':[digest(f) for f in sorted(runtime.glob('*.so'))]},indent=2)+'\n')
 env=dict(os.environ,LD_LIBRARY_PATH=str(runtime),CLANG_MODULE_CACHE_PATH=str(out/'module-cache'))
 if a.scenario in ['calculator-agent','conversation-agent']:
  node=shutil.which('node')
  if not node: raise RuntimeError('Explicit host Node runtime required for reducer bridge')
  env['ORIVYN_TEST_NODE']=node
  (out/'NODE-RUNTIME.json').write_text(json.dumps({'path':node,'version':subprocess.run([node,'--version'],capture_output=True,text=True,check=True).stdout.strip()},indent=2)+'\n')
 command=[str(a.swiftc),'-swift-version','6','-parse-as-library','-module-cache-path',str(out/'module-cache'),'-I',str(module),'-L',str(runtime),'-lllama','-lggml','-Xlinker','-rpath','-Xlinker',str(runtime),*files,'-o',str(out/'llama-engine-smoke')]
 (out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
 version=subprocess.run([str(a.swiftc),'--version'],capture_output=True,text=True,check=True)
 (out/'TOOLCHAIN.txt').write_text(version.stdout+version.stderr)
 started=time.monotonic();compiled=executed=None
 try:
  with (out/'smoke.log').open('w') as log:
   result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180);compiled=result.returncode
   if compiled==0:
    result=subprocess.run([str(out/'llama-engine-smoke'),str(a.model.resolve()),str(runtime)],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=a.run_timeout);executed=result.returncode
 finally:
  (out/'RESULT.json').write_text(json.dumps({'compileExit':compiled,'runtimeExit':executed,'elapsedSeconds':time.monotonic()-started,'exactProductionSwiftEngine':True,'linuxBackendSetupInDriver':True,'appleFrameworkVerified':False,'iPhoneVerified':False},indent=2)+'\n')
 print((out/'smoke.log').read_text());return result.returncode
if __name__=='__main__':raise SystemExit(main())
