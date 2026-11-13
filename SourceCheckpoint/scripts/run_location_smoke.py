#!/usr/bin/env python3
"""Execute exact extracted OneShotLocationService/protocol with explicit boundary doubles.
Real Observation runtime; synthetic location boundary only, not CoreLocation/hardware.
No production source changes.
"""
import argparse,hashlib,json,pathlib,subprocess,os

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 source=root/'JarvisEVO/Services/OneShotLocationService.swift';raw=source.read_text()
 start=raw.index('@MainActor\nprotocol LocationDriver:')
 end=raw.index('/// Created on the main run loop only after a tap.')
 body=raw[start:end]
 extracted='import Foundation\nimport Observation\n\n'+body
 (out/'OneShotLocationExtracted.swift').write_text(extracted)
 manifest=[{'source':'JarvisEVO/Services/OneShotLocationService.swift','sha256':hashlib.sha256(source.read_bytes()).hexdigest()}, {'extracted':'OneShotLocationExtracted.swift','sha256':hashlib.sha256(extracted.encode()).hexdigest(),'bodyExact':body in raw,'excluded':'CoreLocation SystemLocationDriver adapter'}]
 files=[str(out/'OneShotLocationExtracted.swift')]
 for name in ['JarvisEVO/Core/LocationSnapshot.swift']:
  b=(root/name).read_bytes();dest=out/pathlib.Path(name).name;dest.write_bytes(b);files.append(str(dest));manifest.append({'source':name,'sha256':hashlib.sha256(b).hexdigest(),'compiledUnchanged':True})
 template=(root/'scripts/swift-smoke/LocationSmoke.swift').read_text();driver=template
 (out/'LocationSmoke.swift').write_text(driver);files.append(str(out/'LocationSmoke.swift'));manifest.append({'source':'scripts/swift-smoke/LocationSmoke.swift','sha256':hashlib.sha256(template.encode()).hexdigest(),'explicitBoundaryDoubles':True})
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 env=dict(os.environ,HOME=str(out/'home'),TMPDIR=str(out/'tmp'))
 for n in ['home','tmp']:(out/n).mkdir()
 version=subprocess.run([a.swiftc,'--version'],capture_output=True,text=True,check=True);(out/'TOOLCHAIN.txt').write_text(version.stdout+version.stderr)
 command=[a.swiftc,'-swift-version','6','-parse-as-library','-static-stdlib','-module-cache-path',str(out/'module-cache'),*files,'-o',str(out/'location-smoke')];(out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
 with (out/'compile.log').open('w') as log:r=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 report={'compileExit':r.returncode,'runExit':None}
 if r.returncode==0:
  r=subprocess.run([str(out/'location-smoke')],env=env,capture_output=True,text=True,timeout=30);(out/'result.json').write_text(r.stdout);(out/'runtime-stderr.txt').write_text(r.stderr);report['runExit']=r.returncode
 (out/'STATUS.json').write_text(json.dumps(report,indent=2)+'\n');print((out/'compile.log').read_text());print((out/'result.json').read_text() if (out/'result.json').exists() else 'No runtime result');return r.returncode
if __name__=='__main__':raise SystemExit(main())
