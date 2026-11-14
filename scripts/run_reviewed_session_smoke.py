#!/usr/bin/env python3
"""Compile production LocalAgentSession with Linux Node/AppModel/provider unit scaffolds; no model/native iOS claim."""
import argparse,pathlib,runpy,subprocess,shutil,os
p=argparse.ArgumentParser();p.add_argument('--static-stdlib',action='store_true');p.add_argument('--swiftc',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
sources=runpy.run_path(str(root/'scripts/run_foundation_tests.py'))['SOURCES']+['JarvisEVO/Core/LocalHeavyWork.swift','JarvisEVO/Services/LocalAgentSession.swift','JarvisEVO/Services/LocalReadTools.swift','scripts/swift-smoke/ReviewedSessionOwnershipSmoke.swift']
for resource in ['JarvisEVO/Resources/LocalAgentCore.js','scripts/swift-smoke/CalculatorAgentCore.cjs']:shutil.copy(root/resource,out/pathlib.Path(resource).name)
copied=[]
for source in dict.fromkeys(sources):
 target=out/pathlib.Path(source).name;shutil.copy(root/source,target);copied.append(str(target))
command=[a.swiftc,*(['-static-stdlib'] if a.static_stdlib else []),'-swift-version','6','-parse-as-library','-module-cache-path',str(out/'cache'),*copied,'-o',str(out/'session-smoke')]
with (out/'smoke.log').open('w') as log:
 typecheck=[a.swiftc,'-swift-version','6','-typecheck','-parse-as-library','-module-cache-path',str(out/'cache'),*copied]
 result=subprocess.run(typecheck,stdout=log,stderr=subprocess.STDOUT)
 print('Production session typecheck exit: '+str(result.returncode),file=log,flush=True)
 if result.returncode==0:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
 if result.returncode==0:result=subprocess.run([str(out/'session-smoke')],stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,ORIVYN_TEST_NODE=shutil.which('node')),timeout=30)
print((out/'smoke.log').read_text());raise SystemExit(result.returncode)
