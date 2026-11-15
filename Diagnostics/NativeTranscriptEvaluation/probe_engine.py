"""Actual engine rejection and normal-chat regression probes. No mock model."""
import json,os,pathlib,shutil,subprocess,time,uuid
out=pathlib.Path(os.environ['EVIDENCE_DIR'])/'engine-probes';out.mkdir()
engine=os.environ['NATIVE_ENGINE_CLI'];model=pathlib.Path(os.environ['DIAGNOSTIC_MODEL'])
runtime=str(pathlib.Path(os.environ['LLAMA_SOURCE'])/'build/bin')
cid=str(uuid.uuid4());goal='Find the saved Juniper register and read its second message.'
state={'id':str(uuid.uuid4()),'goal':goal,'status':'ready','revision':0,'steps':0,'history':[]}
body={'state':json.dumps(state),'scope':{'query':'Juniper register','messageIndex':1}}
scratch=out/'temporary';scratch.mkdir()
results=[]
def probe(name,request,path,expected=None):
 p=subprocess.run([engine,str(path),runtime],input=json.dumps(request),capture_output=True,text=True,timeout=240,env={**os.environ,'TMPDIR':str(scratch.resolve())})
 (out/(name+'.stdout')).write_text(p.stdout);(out/(name+'.stderr')).write_text(p.stderr)
 if expected:
  assert p.returncode!=0 and not p.stdout.strip() and expected in p.stderr,(name,p.returncode,p.stdout,p.stderr[-1000:])
 else:
  assert p.returncode==0 and ('cancelled without a partial decision' if name=='cancel-after-sealing' else 'hello') in json.loads(p.stdout)['decision'].lower(),(name,p.stderr[-1000:])
 assert not list(scratch.glob('OrivynNativeModel-*')),name+' leaked an owned model copy'
 results.append({'name':name,'passed':True,'exit':p.returncode,'expected':expected})
probe('conflicting-mode',{**body,'conflictingMode':True},model,'invalidState')
large={**state,'revision':2,'steps':1,'history':[{'operationID':'op1','name':'search_conversations','arguments':{'query':'Juniper register','limit':1},'outcome':'succeeded','result':json.dumps({'matches':[{'id':cid,'title':'Juniper register','excerpt':'𠀀'*700}]},ensure_ascii=False,separators=(',',':'))}]}
probe('complete-token-budget',{**body,'state':json.dumps(large,ensure_ascii=False)},model,'promptTooLong')
# A valid GGUF plus one trailing byte still loads but has the wrong actual hash.
other=out/'unknown-model.gguf'
try:
 shutil.copyfile(model,other)
 with other.open('ab') as f:f.write(b'X')
 probe('actual-model-hash',body,other,'integrityMismatch')
finally:
 other.unlink(missing_ok=True)
# Replace the caller's source after the private copy is sealed, before inference
# completes. The model must continue from its owned bytes, never reopen the source.
replacement=out/'replace-during-load.gguf'
child=None
try:
 shutil.copyfile(model,replacement)
 child=subprocess.Popen([engine,str(replacement),runtime],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env={**os.environ,'TMPDIR':str(scratch.resolve())})
 child.stdin.write(json.dumps(body));child.stdin.close()
 deadline=time.monotonic()+60;sealed=False
 while time.monotonic()<deadline and child.poll() is None:
  for candidate in scratch.glob('OrivynNativeModel-*/model.gguf'):
   if candidate.stat().st_mode & 0o777 == 0o400:
    changed=out/'changed-source';changed.write_bytes(b'not a GGUF')
    os.replace(changed,replacement);sealed=True;break
  if sealed:break
  time.sleep(0.05)
 assert sealed,'No sealed private snapshot observed'
 child.stdin=None
 stdout,stderr=child.communicate(timeout=240)
 (out/'source-replacement.stdout').write_text(stdout);(out/'source-replacement.stderr').write_text(stderr)
 assert child.returncode==0,(child.returncode,stderr[-1000:])
 decision=json.loads(json.loads(stdout)['decision'])
 assert decision['type']=='tool' and decision['name']=='search_conversations',decision
 assert not list(scratch.glob('OrivynNativeModel-*')),'source-replacement leaked snapshot'
 results.append({'name':'source-replacement-after-sealing','passed':True,'exit':child.returncode})
finally:
 if child is not None and child.poll() is None:child.kill();child.wait()
 replacement.unlink(missing_ok=True)
probe('cancel-after-sealing',{**body,'cancelProbe':True},model)
probe('regular-chat-preserved',{**body,'regularProbe':True},model)
(out/'summary.json').write_text(json.dumps(results,indent=2));print(json.dumps(results))
