"""Actual engine rejection and normal-chat regression probes. No mock model."""
import json,os,pathlib,shutil,subprocess,uuid
out=pathlib.Path(os.environ['EVIDENCE_DIR'])/'engine-probes';out.mkdir()
engine=os.environ['NATIVE_ENGINE_CLI'];model=pathlib.Path(os.environ['DIAGNOSTIC_MODEL'])
runtime=str(pathlib.Path(os.environ['LLAMA_SOURCE'])/'build/bin')
cid=str(uuid.uuid4());goal='Find the saved Juniper register and read its second message.'
state={'id':str(uuid.uuid4()),'goal':goal,'status':'ready','revision':0,'steps':0,'history':[]}
body={'state':json.dumps(state),'scope':{'query':'Juniper register','messageIndex':1}}
results=[]
def probe(name,request,path,expected=None):
 p=subprocess.run([engine,str(path),runtime],input=json.dumps(request),capture_output=True,text=True,timeout=240)
 (out/(name+'.stdout')).write_text(p.stdout);(out/(name+'.stderr')).write_text(p.stderr)
 if expected:
  assert p.returncode!=0 and not p.stdout.strip() and expected in p.stderr,(name,p.returncode,p.stdout,p.stderr[-1000:])
 else:
  assert p.returncode==0 and 'hello' in json.loads(p.stdout)['decision'].lower(),(name,p.stderr[-1000:])
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
probe('regular-chat-preserved',{**body,'regularProbe':True},model)
(out/'summary.json').write_text(json.dumps(results,indent=2));print(json.dumps(results))
