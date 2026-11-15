#!/usr/bin/env python3
"""Exact production Swift native-read actor or admission harness; Linux only."""
import argparse, hashlib, json, pathlib, runpy, subprocess
p=argparse.ArgumentParser(description=__doc__)
for key in ['swiftc','llama-source','tools-header','library','output']:p.add_argument('--'+key,required=True,type=pathlib.Path)
p.add_argument('--policy',type=int,choices=[1,2],default=1);p.add_argument('--model',type=pathlib.Path);p.add_argument('--admission',action='store_true');a=p.parse_args()
if not a.admission and not a.model:p.error('--model is required for real inference')
r=pathlib.Path(__file__).resolve().parents[1];o=a.output.resolve();o.mkdir(parents=True,exist_ok=False)
sources=runpy.run_path(str(r/'scripts/run_llama_engine_smoke.py'))['SOURCES'];sources=[x for x in sources if not x.endswith('LlamaEngineSmoke.swift')]
sources+=['scripts/swift-smoke/'+('NativeReadAdmissionSmoke.swift' if a.admission else 'NativeReadSmoke.swift')]
if a.admission:sources+=['JarvisEVO/Providers/Local/LocalAIProvider.swift','JarvisEVO/Services/VerifiedLocalReadSession.swift']
mod=o/'llama';mod.mkdir();(mod/'module.modulemap').write_text(f'module llama [system] {{ header "{a.llama_source.resolve()}/include/llama.h" header "{a.tools_header.resolve()}" export * }}\n')
c=[str(a.swiftc.absolute()),'-swift-version','6','-static-stdlib','-DORIVYN_NATIVE_TOOLS','-parse-as-library','-I',str(mod),'-Xcc','-I'+str(a.llama_source.resolve()/'ggml/include'),str(a.library.resolve()),'-Xlinker','-rpath','-Xlinker',str(a.library.resolve().parent),*[str(r/x) for x in sources],'-o',str(o/'smoke')]
(o/'COMMAND.json').write_text(json.dumps(c,indent=2));(o/'SOURCE-MANIFEST.json').write_text(json.dumps({x:hashlib.sha256((r/x).read_bytes()).hexdigest() for x in sources},indent=2))
with (o/'compile.log').open('w') as log:result=subprocess.run(c,stdout=log,stderr=log)
if result.returncode:raise SystemExit(result.returncode)
with (o/'smoke.log').open('w') as out,(o/'runtime.log').open('w') as err:result=subprocess.run([str(o/'smoke')]+([] if a.admission else [str(a.model.resolve()),str(a.policy)]),stdout=out,stderr=err,timeout=180)
(o/'RESULT.json').write_text(json.dumps({'exit':result.returncode,'productionSwiftSources':True,'mode':'host-admission' if a.admission else 'actual-native-inference','AppleVerified':False},indent=2));print((o/'smoke.log').read_text());raise SystemExit(result.returncode)
