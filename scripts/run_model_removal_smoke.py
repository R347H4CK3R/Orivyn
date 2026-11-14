#!/usr/bin/env python3
"""Exact extracted model removal with real file transaction and controlled descriptor lookup.
No real model data, network, full LocalModelStore or iOS verification.
"""
import argparse, hashlib, json, os, pathlib, subprocess
SOURCES = ['JarvisEVO/Core/LocalModelRemovalPlan.swift','JarvisEVO/Providers/Local/LocalModelCatalog.swift','JarvisEVO/Providers/Local/LocalModelCatalogData.swift','JarvisEVO/Providers/Local/ModelInstallTransaction.swift','scripts/swift-smoke/ModelRemovalSmoke.swift']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 manifest=[];files=[]
 raw=(root/'JarvisEVO/Providers/Local/LocalModelStore.swift').read_text()
 start=raw.index('    func remove(');end=raw.index('\n    }\n',start)+len('\n    }')
 method=raw[start:end]
 (out/'remove.swift').write_text(method+'\n')
 manifest.append({'source':'JarvisEVO/Providers/Local/LocalModelStore.swift','sha256':hashlib.sha256(raw.encode()).hexdigest(),'extractedMethodSHA256':hashlib.sha256(method.encode()).hexdigest()})
 for name in SOURCES:
  b=(root/name).read_bytes();original=b;
  if name.endswith('/ModelRemovalSmoke.swift'): b=b.decode().replace('    // PRODUCTION_METHOD',method).encode()
  dest=out/pathlib.Path(name).name;dest.write_bytes(b);files.append(str(dest));manifest.append({'source':name,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)})
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 env=dict(os.environ,HOME=str(out/'home'),XDG_CONFIG_HOME=str(out/'config'),TMPDIR=str(out/'tmp'))
 for name in ['home','config','tmp']:(out/name).mkdir()
 command=[a.swiftc,'-swift-version','6','-parse-as-library','-static-stdlib','-module-cache-path',str(out/'module-cache'),*files,'-o',str(out/'model-removal-smoke')]
 (out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
 with (out/'smoke.log').open('w') as log:
  result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
  if result.returncode==0:result=subprocess.run([str(out/'model-removal-smoke')],env=env,stdout=log,stderr=subprocess.STDOUT)
 print((out/'smoke.log').read_text());return result.returncode
if __name__=='__main__':raise SystemExit(main())
