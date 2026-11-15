const test=require('node:test'),assert=require('node:assert/strict');
const api=require('../../JarvisEVO/Resources/LocalAgentCore.js');
const id='12345678-1234-1234-1234-123456789abc';
const tool=(name='get_app_info',args={})=>JSON.stringify({type:'tool',name,arguments:args});
const answer=JSON.stringify({type:'answer',text:'A proposed answer'});
function result(s,text){s=api.acceptDecision(s,tool());return api.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result:text}));}
const facts=s=>JSON.parse(api.prompt(s).split('UNTRUSTED_RESULTS_JSON=')[1].split('\n')[0]);
test('answer sees a complete fitting result instead of cycling through forgotten pages',()=>{
 let s=result(api.create('Read complete evidence',id),'x'.repeat(700)+'TAIL');
 assert.equal(facts(s)[0].result,'x'.repeat(700)+'TAIL');
 s=api.acceptDecision(s,answer);assert.equal(JSON.parse(s).status,'answered');
 assert.equal(JSON.parse(s).steps,1);assert.equal(JSON.parse(s).internalReads,0);
});
test('later successful results cannot conceal complete earlier evidence',()=>{
 let s=result(api.create('Read complete evidence',id),'x'.repeat(800)+'TAIL');s=result(s,'newest');
 s=api.acceptDecision(s,tool('read_result',{step:1,offset:768}));
 assert.deepEqual(facts(s).map(x=>x.result),['x'.repeat(800)+'TAIL','newest']);
 assert.equal(JSON.parse(api.acceptDecision(s,answer)).status,'answered');
});
test('complete simultaneous evidence preserves multibyte contents',()=>{
 const text='🦊'.repeat(200)+'END',s=result(api.create('Read Unicode',id),text);
 assert.equal(facts(s)[0].result,text);assert.ok(Buffer.byteLength(api.prompt(s))<=3500);
 assert.equal(JSON.parse(api.acceptDecision(s,answer)).status,'answered');
});
test('legacy exposure migration retains compatibility without claiming model memory',()=>{
 let s=JSON.parse(result(api.create('Read evidence',id),'x'.repeat(600)));delete s.exposedThrough;
 const migrated=api.recover(JSON.stringify(s));assert.equal(JSON.parse(migrated).revision,s.revision+1);
 assert.deepEqual(JSON.parse(migrated).exposedThrough,[0]);assert.equal(api.recover(migrated),migrated);
 assert.equal(facts(migrated)[0].result,'x'.repeat(600));assert.equal(JSON.parse(api.acceptDecision(migrated,answer)).status,'answered');
});
test('malformed legacy coverage still cannot pass state validation',()=>{
 const s=JSON.parse(result(api.create('Read evidence',id),'🦊'));
 for(const exposedThrough of [[1],[-1],[5],[],[4,0]])assert.throws(()=>api.recover(JSON.stringify({...s,exposedThrough})));
});
test('exhausted cursor budget does not hide evidence or require pseudo-memory to answer',()=>{
 let s=result(api.create('Read complete evidence',id),'x'.repeat(800));
 for(let i=0;i<102;i++)s=api.acceptDecision(s,tool('read_result',{step:1,offset:0}));
 assert.equal(facts(s)[0].result,'x'.repeat(800));assert.equal(JSON.parse(api.acceptDecision(s,answer)).status,'answered');
 assert.equal(JSON.parse(api.acceptDecision(s,tool('read_result',{step:1,offset:0}))).status,'failed');
});
test('legacy six-result overflow preserves all evidence and cannot authorize an answer',()=>{
 let s=api.create('Read all results',id);for(let i=0;i<6;i++)s=result(s,'small');
 const old=JSON.parse(s);old.history.forEach(h=>h.result='水水'.repeat(682)+'END');old.exposedThrough=old.history.map(h=>Buffer.byteLength(h.result));
 s=api.recover(JSON.stringify(old));assert.equal(JSON.parse(s).status,'failed');assert.equal(JSON.parse(s).history.length,6);
 assert.deepEqual(JSON.parse(s).history.map(h=>h.result),old.history.map(h=>h.result));assert.throws(()=>api.acceptDecision(s,answer));
});
