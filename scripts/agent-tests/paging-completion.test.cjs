const test=require('node:test'),assert=require('node:assert/strict');
const api=require('../../JarvisEVO/Resources/LocalAgentCore.js');
const id='12345678-1234-1234-1234-123456789abc';
const tool=(name='get_app_info',args={})=>JSON.stringify({type:'tool',name,arguments:args});
const answer=JSON.stringify({type:'answer',text:'A proposed answer'});
function result(s,text){s=api.acceptDecision(s,tool());return api.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result:text}));}
const page=s=>JSON.parse(api.prompt(s).split('UNTRUSTED_PAGE_JSON=')[1]);
test('premature answer advances unread evidence instead of completing',()=>{
 let s=result(api.create('Read complete evidence',id),'x'.repeat(700)+'TAIL');
 s=api.acceptDecision(s,answer);
 assert.equal(JSON.parse(s).status,'ready');assert.equal(page(s).offset,256);
 s=api.acceptDecision(s,answer);assert.equal(page(s).offset,512);
 s=api.acceptDecision(s,answer);assert.equal(JSON.parse(s).status,'answered');
 assert.equal(JSON.parse(s).steps,1);assert.equal(JSON.parse(s).internalReads,2);
});
test('later successful results cannot conceal unread earlier result pages',()=>{
 let s=result(api.create('Read complete evidence',id),'x'.repeat(800)+'TAIL');
 s=result(s,'newest');
 s=api.acceptDecision(s,tool('read_result',{step:1,offset:768}));
 s=api.acceptDecision(s,answer);
 assert.equal(JSON.parse(s).status,'ready');assert.equal(page(s).step,1);assert.equal(page(s).offset,256);
});
test('automatic paging preserves UTF-8 boundaries and covers all data',()=>{
 let s=result(api.create('Read Unicode',id),'🦊'.repeat(200)+'END');
 let found=page(s).text,reads=0;
 while(true){s=api.acceptDecision(s,answer);if(JSON.parse(s).status==='answered')break;found+=page(s).text;assert.equal(page(s).offset%4,0);assert.ok(++reads<10);}
 assert.equal(found,'🦊'.repeat(200)+'END');
});
test('paging state migration adds conservative coverage with one durable revision',()=>{
 let s=JSON.parse(result(api.create('Read evidence',id),'x'.repeat(600)));
 delete s.exposedThrough;
 const migrated=api.recover(JSON.stringify(s));
 assert.equal(JSON.parse(migrated).revision,s.revision+1);
 assert.deepEqual(JSON.parse(migrated).exposedThrough,[0]);
 assert.equal(api.recover(migrated),migrated);
 assert.equal(JSON.parse(api.acceptDecision(migrated,answer)).status,'ready');
});
test('malformed evidence coverage cannot pass state validation',()=>{
 const s=JSON.parse(result(api.create('Read evidence',id),'🦊'));
 for(const exposedThrough of [[1],[-1],[5],[],[4,0]])assert.throws(()=>api.recover(JSON.stringify({...s,exposedThrough})));
});
test('exhausted internal-read budget fails without accepting a premature answer',()=>{
 let s=result(api.create('Read complete evidence',id),'x'.repeat(800));
 for(let i=0;i<102;i++)s=api.acceptDecision(s,tool('read_result',{step:1,offset:0}));
 s=api.acceptDecision(s,answer);
 assert.equal(JSON.parse(s).status,'failed');assert.equal(JSON.parse(s).answer,null);
 assert.match(JSON.parse(s).error,/before all evidence was exposed/);
});
test('six maximum Unicode results can be exposed within existing read budget',()=>{
 let s=api.create('Read all results',id);
 for(let i=0;i<6;i++)s=result(s,'水水'.repeat(682)+'END');
 let loops=0;
 while(JSON.parse(s).status==='ready'){
  s=api.acceptDecision(s,answer);assert.ok(++loops<=103);
 }
 assert.equal(JSON.parse(s).status,'answered');
 assert.equal(JSON.parse(s).steps,6);assert.ok(JSON.parse(s).internalReads<=102);
});
