#!/usr/bin/env python3
"""Compile exact production parser/converter and test synthetic fresh-process RSS.
No downloads, private files, ZIP/SQLite operations, or iPhone verification.
"""
import argparse,hashlib,json,os,pathlib,subprocess,sys
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--swiftc',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
names=['ArchiveReadBuffer','ChatGPTRecordStream','ChatGPTConversationRestore','Conversation','MemoryNote','ImageOCRResult','OCRLineEvidence']
sources=['JarvisEVO/Core/'+n+'.swift' for n in names]+['Diagnostics/ImportResources/ImportResourceProbe.swift']
manifest=[];files=[]
for source in sources:
 b=(root/source).read_bytes();target=out/pathlib.Path(source).name;target.write_bytes(b);files.append(str(target));manifest.append({'source':source,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
(out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Build large fixtures in a separate process. Keeping the orchestrator small
# avoids inheriting its generator's high RSS into fork/exec measurement children.
generator = 'import json,pathlib,sys\nout=pathlib.Path(sys.argv[1])\nr={\'id\':\'00000000-0000-0000-0000-000000000001\',\'current_node\':\'n\',\'create_time\':1,\'update_time\':1,\'mapping\':{\'n\':{\'parent\':None,\'message\':{\'id\':\'00000000-0000-0000-0000-000000000002\',\'author\':{\'role\':\'user\'},\'create_time\':1,\'content\':{\'content_type\':\'text\',\'parts\':[\'Synthetic visible message\']}}}}}\n# Generate outside measured Swift processes. All originals are synthetic and retained.\nr[\'unused_metadata\']=[{\'a\':\'x\'*32,\'b\':1,\'c\':False} for _ in range(279000)]\ndense=json.dumps([r],separators=(\',\',\':\')).encode(); (out/\'dense.json\').write_bytes(dense)\nr.pop(\'unused_metadata\')\nbase=json.dumps(r,separators=(\',\',\':\'))\n(out/\'malformed.json\').write_text(\'[\'+base[:-1]+\',"unknown":[true,]}]\')\nr[\'mapping\'][\'n\'][\'message\'][\'content\'][\'parts\']=[{\'too_many\':list(range(20001))}]\n(out/\'opaque-limit.json\').write_text(json.dumps([r],separators=(\',\',\':\')))\n\nr[\'mapping\'][\'n\'][\'message\'][\'content\'][\'parts\']=[\'Synthetic visible message\'+\'x\'*2000]\nwith (out/\'many.json\').open(\'w\') as f:\n f.write(\'[\')\n for i in range(10000):\n  r[\'id\']=\'00000000-0000-0000-0000-\'+format(i+1,\'012d\')\n  r[\'mapping\'][\'n\'][\'message\'][\'id\']=\'00000000-0000-0000-0000-\'+format(i+100001,\'012d\')\n  if i:f.write(\',\')\n  f.write(json.dumps(r,separators=(\',\',\':\')))\n f.write(\']\')\n'
generator += """
r['mapping']['n']['message']['content']['parts']=['Synthetic visible message'+'x'*50000]
with (out/'longstream.json').open('w') as f:
 f.write('[')
 for i in range(10000):
  r['id']='00000000-0000-0000-0000-'+format(i+1,'012d')
  r['mapping']['n']['message']['id']='00000000-0000-0000-0000-'+format(i+100001,'012d')
  if i:f.write(',')
  f.write(json.dumps(r,separators=(',',':')))
 f.write(']')
"""
subprocess.run([sys.executable, '-c', generator, str(out)], check=True)
def file_sha256(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
 return h.hexdigest()
fixtures=[{'path':f.name,'bytes':f.stat().st_size,'sha256':file_sha256(f)} for f in sorted(out.glob('*.json')) if f.name!='SOURCE-MANIFEST.json']
(out/'FIXTURES.json').write_text(json.dumps(fixtures,indent=2)+'\n')
exe=out/'import-resource-probe';command=[str(a.swiftc),'-O','-swift-version','6','-parse-as-library','-module-cache-path',str(out/'module-cache'),*files,'-o',str(exe)]
(out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
(out/'TOOLCHAIN.txt').write_text(subprocess.check_output([str(a.swiftc),'--version'],text=True))
with (out/'compile.log').open('w') as log: compiled=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
results={'compileExit':compiled,'cases':{},'iPhoneVerified':False,'fullZIPPipelineVerified':False}
if compiled==0:
 for mode in ['dense','many','longstream','malformed','opaque-limit']:
  with (out/(mode+'.log')).open('w') as log: code=subprocess.run([str(exe),str(out/(mode+'.json')),mode],stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
  results['cases'][mode]=code
(out/'RESULT.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
raise SystemExit(0 if compiled==0 and len(results['cases'])==5 and all(c==0 for c in results['cases'].values()) else 1)
