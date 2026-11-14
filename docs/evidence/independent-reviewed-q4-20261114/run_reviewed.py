#!/usr/bin/env python3
import argparse,hashlib,json,os,pathlib,shutil,subprocess,time
p=argparse.ArgumentParser()
for key in ['prepared','model','runtime','output']:p.add_argument('--'+key,type=pathlib.Path,required=True)
p.add_argument('--exclusive-slot-authorized',action='store_true',required=True)
a=p.parse_args();prepared=a.prepared.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
fixtures=json.loads((prepared/'sealed-cases.json').read_text())+[json.loads((prepared/'supplemental-case.json').read_text())]
intents=json.loads((prepared/'reviewed-intents.json').read_text())
def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
 return {'path':str(path.resolve()),'bytes':path.stat().st_size,'sha256':h.hexdigest()}
model=digest(a.model);assert model['sha256']=='d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5'
(out/'RUNTIME-MODEL-MANIFEST.json').write_text(json.dumps({'model':model,'runtime':[digest(x) for x in sorted(a.runtime.glob('*.so'))],'driver':digest(prepared/'holdout-driver'),'inputs':[digest(prepared/name) for name in ['SOURCE-MANIFEST.json','sealed-cases.json','supplemental-case.json','reviewed-intents.json','proposal_approval.py','approve_actual.py','IndependentReviewedDriver.swift']]},indent=2)+'\n')
env=dict(os.environ,ORIVYN_TEST_NODE=shutil.which('node'),ORIVYN_TEST_PYTHON=shutil.which('python3'),LD_LIBRARY_PATH=str(a.runtime.resolve()));results=[]
for fixture in fixtures:
 case=fixture['id'];started=time.monotonic();timedout=False
 with (out/(case+'.stdout')).open('w') as stdout,(out/(case+'.stderr')).open('w') as stderr:
  try:r=subprocess.run([str(prepared/'holdout-driver'),str(a.model.resolve()),str(a.runtime.resolve()),case,str(out/case)],env=env,stdout=stdout,stderr=stderr,timeout=720);status=r.returncode
  except subprocess.TimeoutExpired:status=None;timedout=True
 directory=out/case;approval=json.loads((directory/'APPROVAL.json').read_text()) if (directory/'APPROVAL.json').exists() else {'approved':False,'reason':'proposal-schema-or-generation-failure'}
 statepath=directory/('FINAL-STATE.json' if (directory/'FINAL-STATE.json').exists() else 'STOPPED-STATE.json');state=json.loads(statepath.read_text()) if statepath.exists() else None
 history=state.get('history',[]) if state else []
 missing_safe=case=='h09' and approval['approved'] and state is not None and state.get('status')!='answered' and len(history)==1 and history[0]['name']=='search_conversations' and json.loads(history[0]['result'])['matches']==[]
 completed=status==0
 result={'case':case,'exit':status,'timeout':timedout,'elapsedSeconds':time.monotonic()-started,'approval':approval,'contractCompletion':completed,'answerQuality':'exact-pass' if completed else 'not-completed','safeRefusal':'expected-missing-target-safe-incomplete' if missing_safe else ('wrong-proposal-contained-not-capability-success' if not approval['approved'] and state is None else 'not-established' if not completed else 'not-applicable'),'expectedOutcomeMet':completed or missing_safe,'kindProvenance':'predeclared-user-input-not-model-classification','userSelectedKind':intents[case]['userSelectedKind'],'AppleVerified':False}
 results.append(result);(out/'RESULTS.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(result),flush=True)
(out/'EVIDENCE-HASHES.json').write_text(json.dumps([digest(x) for x in sorted(out.rglob('*')) if x.is_file()],indent=2)+'\n')
raise SystemExit(0 if all(x['expectedOutcomeMet'] for x in results) else 1)
