#!/usr/bin/env python3
"""Snapshot exact production inputs and emit a compile command. Never runs a model."""
import argparse,hashlib,json,pathlib,runpy,shutil,subprocess
p=argparse.ArgumentParser(description=__doc__)
for key in ['source','runtime','headers','swiftc','output']:p.add_argument('--'+key,type=pathlib.Path,required=True)
a=p.parse_args();here=pathlib.Path(__file__).resolve().parent;root=a.source.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
freeze=json.loads((here/'DESIGN-FREEZE.json').read_text());assert hashlib.sha256((here/'sealed-cases.json').read_bytes()).hexdigest()==freeze['fixtureSHA256']
sources=runpy.run_path(str(root/'scripts/run_llama_engine_smoke.py'))['SOURCES']+runpy.run_path(str(root/'scripts/run_foundation_tests.py'))['SOURCES']+['JarvisEVO/Services/LocalReadTools.swift']
sources=list(dict.fromkeys(x for x in sources if not x.startswith('scripts/swift-smoke/')))
manifest=[];files=[]
for name in sources:
 data=(root/name).read_bytes();dest=out/pathlib.Path(name).name;dest.write_bytes(data);files.append(str(dest));manifest.append({'source':name,'sha256':hashlib.sha256(data).hexdigest()})
for name in ['JarvisEVO/Resources/LocalAgentDecision.gbnf','JarvisEVO/Resources/LocalAgentCore.js','scripts/swift-smoke/CalculatorAgentCore.cjs']:
 data=(root/name).read_bytes();(out/pathlib.Path(name).name).write_bytes(data);manifest.append({'source':name,'sha256':hashlib.sha256(data).hexdigest()})
for name in ['IndependentReviewedDriver.swift','sealed-cases.json','supplemental-case.json','reviewed-intents.json','proposal_approval.py','approve_actual.py','DESIGN-FREEZE.json']:
 data=(here/name).read_bytes();(out/name).write_bytes(data);manifest.append({'source':'independent-evaluator/'+name,'sha256':hashlib.sha256(data).hexdigest()})
files.append(str(out/'IndependentReviewedDriver.swift'));module=out/'llama';module.mkdir();shutil.copytree(a.headers,module/'include')
(module/'module.modulemap').write_text('module llama [system] { header "include/llama.h" link "llama" export * }\n')
for file in (module/'include').glob('*.h'):manifest.append({'source':'runtime-header/'+file.name,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
command=[str(a.swiftc.absolute()),'-swift-version','6','-parse-as-library','-module-cache-path',str(out/'module-cache'),'-I',str(module),'-L',str(a.runtime.resolve()),'-lllama','-lggml','-Xlinker','-rpath','-Xlinker',str(a.runtime.resolve()),*files,'-o',str(out/'holdout-driver')]
(out/'COMPILE-COMMAND.json').write_text(json.dumps(command,indent=2)+'\n');(out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
commit=subprocess.run(['git','-C',str(root),'rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip()
dirty=subprocess.run(['git','-C',str(root),'diff','--quiet']).returncode!=0
(out/'SOURCE-STATE.json').write_text(json.dumps({'commit':commit,'trackedChanges':dirty,'preparedOnly':True,'modelRuns':0,'AppleVerified':False},indent=2)+'\n')
print('Prepared exact source snapshot and compile command only; no compile or inference executed.')
