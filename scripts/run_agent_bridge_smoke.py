#!/usr/bin/env python3
"""Execute exact Swift storage/budget code across a process boundary with the JS reducer.
No model inference, JSCore, Apple framework, paid CI, or downloaded dependency.
"""
import argparse, hashlib, json, pathlib, subprocess
SOURCES = ['JarvisEVO/Core/MCPToolSchema.swift','JarvisEVO/Core/MCPTypes.swift','JarvisEVO/Core/LocalAgentError.swift',
 'JarvisEVO/Core/LocalToolResultBudget.swift','JarvisEVO/Services/LocalAgentStore.swift',
 'scripts/swift-smoke/AgentBridge.swift','JarvisEVO/Resources/LocalAgentCore.js',
 'scripts/agent-tests/bridge-smoke.cjs']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 manifest=[];swift=[]
 for name in SOURCES:
  b=(root/name).read_bytes();dest=out/pathlib.Path(name).name;dest.write_bytes(b)
  manifest.append({'source':name,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)})
  if dest.suffix=='.swift':swift.append(str(dest))
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 commands=[[a.swiftc,'-swift-version','6','-parse-as-library','-module-cache-path',str(out/'module-cache'),*swift,'-o',str(out/'agent-bridge')],
 ['node',str(out/'bridge-smoke.cjs'),str(out/'agent-bridge'),str(out/'LocalAgentCore.js'),str(out/'records')]]
 (out/'COMMANDS.json').write_text(json.dumps(commands,indent=2)+'\n')
 with (out/'bridge.log').open('w') as log:
  for command in commands:
   result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
   if result.returncode:break
 print((out/'bridge.log').read_text());return result.returncode
if __name__=='__main__':raise SystemExit(main())
