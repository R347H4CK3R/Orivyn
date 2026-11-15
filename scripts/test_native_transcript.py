"""Portable Swift tests + independently rendered pinned Jinja golden equality; no model."""
import argparse,hashlib,importlib.util,json,os,pathlib,subprocess
from jinja2.sandbox import SandboxedEnvironment
p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve()
spec=importlib.util.spec_from_file_location('foundation',root/'scripts/run_foundation_tests.py')
foundation=importlib.util.module_from_spec(spec);spec.loader.exec_module(foundation)
foundation.SOURCES += ['JarvisEVO/Core/NativeToolTranscript.swift','JarvisEVO/Core/NativeToolResponseAdapter.swift']
foundation.TESTS=['Tests/NativeToolTranscriptTests.swift']
foundation.prepare(root,out)
(out/'source-commit.txt').write_text(subprocess.check_output(['git','rev-parse','HEAD'],text=True))
vectors=out/'vectors.json'
with (out/'swift-tests.log').open('w') as log:
 result=subprocess.run(['swift','test','--jobs','2','--package-path',str(out)],stdout=log,stderr=subprocess.STDOUT,env={**os.environ,'NATIVE_TRANSCRIPT_VECTORS':str(vectors)})
print((out/'swift-tests.log').read_text())
if result.returncode:raise SystemExit(result.returncode)
template=(root/'docs/evidence/qwen3-native-tool-template.jinja').read_text()
assert hashlib.sha256(template.encode()).hexdigest()=='87a2728cb8dc9fe424d624542f6060ec05a1d285ebbec578bb078900e33396b5'
env=SandboxedEnvironment(trim_blocks=True,lstrip_blocks=True)
def reject(message):raise ValueError(message)
env.globals['raise_exception']=reject
rows=json.loads(vectors.read_text())
assert len(rows)==3
for i,row in enumerate(rows):
 expected=env.from_string(template).render(messages=row['messages'],tools=row['tools'],add_generation_prompt=True,enable_thinking=False,bos_token='',eos_token='<|im_end|>')
 (out/f'golden-{i}.txt').write_text(expected)
 assert row['prompt']==expected, f'Exact template mismatch at turn{i}'
node=r"""
const fs=require('fs'),core=require(process.argv[1]),rows=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
for(const row of rows){
 let state=core.create(row.messages[1].content,'12345678-1234-1234-1234-123456789abc');
 for(const event of row.history){
  state=core.acceptDecision(state,JSON.stringify({type:'tool',name:event.name,arguments:JSON.parse(event.arguments)}));
  const running=JSON.parse(state);if(running.status!=='running')throw Error('history rejected');
  state=core.recordResult(state,JSON.stringify({operationID:running.pending.operationID,result:event.result}));
 }
 const next=JSON.parse(core.acceptDecision(state,row.decision));
 const decision=JSON.parse(row.decision);
 if(next.status!==(decision.type==='answer'?'answered':'running'))throw Error('adapter decision rejected');
}
console.log('3 adapter decisions accepted through unchanged production reducer; no tool execution');
"""
r=subprocess.run(['node','-e',node,str(root/'JarvisEVO/Resources/LocalAgentCore.js'),str(vectors)],capture_output=True,text=True)
(out/'reducer.log').write_text(r.stdout+r.stderr);print(r.stdout,r.stderr)
if r.returncode:raise SystemExit(r.returncode)
(out/'summary.json').write_text(json.dumps({'goldenPrompts':3,'reducerDecisions':3,'scope':'Portable transcript/parser only; no native engine/model/app integration'},indent=2))
print('PASS exact pinned-template golden equality and unchanged reducer acceptance')
