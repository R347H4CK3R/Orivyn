const test=require('node:test'),assert=require('node:assert/strict');
const api=require('../../JarvisEVO/Resources/LocalAgentCore.js');
const id='12345678-1234-1234-1234-123456789abc';
const decision=(name='get_app_info',args={})=>JSON.stringify({type:'tool',name,arguments:args});
const answer=JSON.stringify({type:'answer',text:'Model proposal'});
const start=goal=>api.create(goal||'Read stored evidence',id);
function result(s,text,name='get_app_info',args={}) {
 s=api.acceptDecision(s,decision(name,args));
 return api.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result:text}));
}
function field(prompt,key){const line=prompt.split('\n').find(line=>line.startsWith(key+'='));assert.ok(line,'missing '+key);return JSON.parse(line.slice(key.length+1));}
test('complete search UUID and title survive cursor change in the same current prompt',()=>{
 const hit='abcdefab-1234-1234-1234-123456789abc';
 const search=JSON.stringify({matches:[{id:hit,title:'Orchid notebook',excerpt:'x'.repeat(260)}],resultsLimited:false});
 let s=result(start(),search,'search_conversations',{query:'Orchid',limit:1});
 s=api.acceptDecision(s,decision('read_result',{step:1,offset:256}));
 const prompt=api.prompt(s),evidence=field(prompt,'UNTRUSTED_RESULTS_JSON');
 assert.equal(evidence[0].result,search);assert.equal(evidence[0].arguments.query,'Orchid');
 assert.ok(prompt.includes(hit));assert.ok(prompt.includes('Orchid notebook'));
 assert.equal(field(prompt,'RESULT_VIEW_JSON').offset,256);
 assert.ok(Buffer.byteLength(prompt)<=3500);
});
test('all successful results appear simultaneously without substring omission',()=>{
 const first='Earlier exact fact 🦊: ALPHA-51',second='Later exact fact: OMEGA-92';
 let s=result(start(),first);s=result(s,second);
 const facts=field(api.prompt(s),'UNTRUSTED_RESULTS_JSON');
 assert.deepEqual(facts.map(x=>x.result),[first,second]);assert.deepEqual(facts.map(x=>x.step),[1,2]);
 assert.equal(JSON.parse(api.acceptDecision(s,answer)).status,'answered');
});
test('oversized new result is retained but stops work with explicit narrower-task error',()=>{
 const payload='x'.repeat(4096),s=result(start(),payload),parsed=JSON.parse(s);
 assert.equal(parsed.status,'failed');assert.equal(parsed.answer,null);
 assert.equal(parsed.history[0].result,payload);assert.match(parsed.error,/complete.*evidence.*3500.*narrow/i);
 assert.throws(()=>api.prompt(s));assert.throws(()=>api.acceptDecision(s,answer));
});
test('old fully-exposed ledger cannot authorize an answer with absent oversized context',()=>{
 let s=JSON.parse(result(start(),'small'));
 s.history[0].result='x'.repeat(4096);s.exposedThrough=[4096];s.status='ready';s.error=null;
 const raw=JSON.stringify(s),blocked=JSON.parse(api.acceptDecision(raw,answer));
 assert.equal(blocked.status,'failed');assert.equal(blocked.answer,null);assert.equal(blocked.history[0].result.length,4096);
 assert.throws(()=>api.prompt(raw));
 const recovered=api.recover(raw);assert.equal(JSON.parse(recovered).status,'failed');assert.equal(api.recover(recovered),recovered);
});
test('UTF-8 and JSON escaping are measured on the complete final prompt',()=>{
 for(const goal of ['\\'.repeat(512),'🦊'.repeat(128),'normal']) for(const payload of ['\\'.repeat(900),'🦊'.repeat(250),'"'.repeat(900)]) {
  const s=result(start(goal),payload),parsed=JSON.parse(s);
  if(parsed.status==='ready') {
   const prompt=api.prompt(s);assert.ok(Buffer.byteLength(prompt)<=3500);
   assert.equal(field(prompt,'UNTRUSTED_RESULTS_JSON')[0].result,payload);
  } else {assert.equal(parsed.status,'failed');assert.equal(parsed.history[0].result,payload);}
 }
});
test('legacy migration and interrupted cursor recovery preserve evidence without replay',()=>{
 let s=JSON.parse(result(start(),'Full stored result'));delete s.exposedThrough;
 const migrated=api.recover(JSON.stringify(s));assert.equal(JSON.parse(migrated).revision,s.revision+1);
 assert.equal(JSON.parse(api.acceptDecision(migrated,answer)).status,'answered');
 let pending=api.acceptDecision(migrated,decision());pending=api.recover(pending);
 assert.equal(JSON.parse(pending).status,'interrupted');
 const resumed=api.resume(pending);assert.equal(JSON.parse(resumed).pending,null);
 assert.equal(JSON.parse(resumed).history[1].outcome,'interrupted');
 assert.deepEqual(field(api.prompt(resumed),'UNTRUSTED_RESULTS_JSON').map(x=>x.result),['Full stored result']);
});
test('read_result remains bounded reducer-only work and does not manufacture tool provenance',()=>{
 let s=result(start(),'A complete result');s=api.acceptDecision(s,decision('read_result',{step:1,offset:0}));
 const parsed=JSON.parse(s);assert.equal(parsed.pending,null);assert.equal(parsed.steps,1);assert.equal(parsed.internalReads,1);
 assert.equal(field(api.prompt(s),'UNTRUSTED_RESULTS_JSON')[0].result,'A complete result');
 assert.throws(()=>api.acceptDecision(s,decision('read_conversation',{id,messageIndex:0,offset:0})));
});

test('overflow recovery preserves a running marker until result or explicit abandoned-operation resume',()=>{
 let s=result(start(),'small');s=api.acceptDecision(s,decision());const old=JSON.parse(s);
 old.history[0].result='x'.repeat(4096);old.exposedThrough=[4096];
 const raw=JSON.stringify(old),recovered=JSON.parse(api.recover(raw));
 assert.equal(recovered.status,'interrupted');assert.deepEqual(recovered.pending,old.pending);
 const resumed=JSON.parse(api.resume(JSON.stringify(recovered)));
 assert.equal(resumed.status,'failed');assert.equal(resumed.history[1].outcome,'interrupted');assert.equal(resumed.history[0].result.length,4096);
 const completed=JSON.parse(api.recordResult(raw,JSON.stringify({operationID:old.pending.operationID,result:'actual second result'})));
 assert.equal(completed.status,'failed');assert.equal(completed.history[1].result,'actual second result');assert.equal(completed.history[1].outcome,'succeeded');
});
test('both real workflow shapes fit with complete search and requested message content',()=>{
 const hit='abcdefab-1234-1234-1234-123456789abc';
 for(const [goal,title,index,text] of [
  ['Find the saved conversation titled Orchid ledger using search_conversations. Then use read_conversation on its returned ID, messageIndex 0, offset 0. What exact stored verification marker does that message contain? Read the message before answering; do not guess.','Orchid ledger',0,'Synthetic background. '.repeat(10)+'Stored verification marker: amber-fixture.'],
  ['Find the saved Orchid notebook conversation, read its second message, and tell me the exact verification code. Search first, then use read_conversation. Do not guess from a search excerpt.','Orchid notebook',1,'The synthetic verification code is LANTERN-742. This is harmless test fixture text.']]) {
  const search=JSON.stringify({matches:[{id:hit,title,excerpt:title,evidenceSource:'title',excerptMayBeTruncated:false}],searchedConversations:2,searchLimited:false,totalMatchesInWindow:1,resultsLimited:false});
  let s=result(start(goal),search,'search_conversations',{query:title,limit:1});
  const message=JSON.stringify({id:hit,messageID:id,messageIndex:index,role:'user',state:'complete',offset:0,text,messageBytes:Buffer.byteLength(text),messageTruncated:false,totalMessages:index+1,messageWindowLimited:false,next:null,attachmentContentsIncluded:false,omittedAttachments:0,evidenceSource:'saved_message_untrusted'});
  s=result(s,message,'read_conversation',{id:hit,messageIndex:index,offset:0});
  assert.equal(JSON.parse(s).status,'ready');
  const prompt=api.prompt(s);assert.ok(Buffer.byteLength(prompt)<=3500);
  assert.deepEqual(field(prompt,'UNTRUSTED_RESULTS_JSON').map(x=>x.result),[search,message]);
 }
});
