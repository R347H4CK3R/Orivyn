#!/usr/bin/env python3
"""macOS exact-source synthetic preservation/RSS acceptance; not iPhone proof."""
import argparse,hashlib,json,os,pathlib,subprocess
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
sources=['JarvisEVO/Core/ArchiveReadBuffer.swift','JarvisEVO/Core/ArchiveRestoreProgress.swift','JarvisEVO/Services/ArchivePreservation.swift','Diagnostics/ImportResources/PreservationAcceptance.swift']
files=[];manifest=[]
for source in sources:
 b=(root/source).read_bytes();target=out/pathlib.Path(source).name;target.write_bytes(b);files.append(str(target));manifest.append({'source':source,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
(out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
exe=out/'preservation-acceptance';command=[str(a.swiftc),'-O','-swift-version','6','-parse-as-library','-module-cache-path',str(out/'module-cache'),*files,'-o',str(exe)]
(out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
with (out/'compile.log').open('w') as log:code=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
results={'compileExit':code,'cases':{},'physicalDeviceVerified':False}
if code==0:
 for size,mode in [(33554432,'complete'),(2200000000,'complete'),(33554432,'cancel')]:
  label=f'{mode}-{size}'
  with (out/(label+'.log')).open('w') as log:
   result=subprocess.run([str(exe),str(size),mode],stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,RUNNER_TEMP=str(out)),timeout=240).returncode
  results['cases'][label]=result
(out/'RESULT.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
raise SystemExit(0 if code==0 and len(results['cases'])==3 and all(v==0 for v in results['cases'].values()) else 1)
