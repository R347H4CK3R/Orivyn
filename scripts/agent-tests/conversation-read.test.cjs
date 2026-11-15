const test=require('node:test'),assert=require('node:assert/strict');
const api=require('../../JarvisEVO/Resources/LocalAgentCore.js');
const id='12345678-1234-1234-1234-123456789abc',hit='abcdefab-1234-1234-1234-123456789abc';
const decision=(name,arguments)=>JSON.stringify({type:'tool',name,arguments});
const read=(id=hit)=>decision('read_conversation',{id,messageIndex:0,offset:0});
function searched(result=JSON.stringify({matches:[{id:hit}]}),name='search_conversations') {
 let s=api.create('Read the matched conversation',id);
 s=api.acceptDecision(s,decision(name,{query:'topic',limit:1}));
 return api.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result}));
}
test('conversation read requires an actual successful returned search ID',()=>{
 assert.throws(()=>api.acceptDecision(api.create('read',id),read()));
 for(const s of [searched('{}'),searched(JSON.stringify({matches:[]})),searched('not JSON'),searched(JSON.stringify({matches:[{id:hit}]}),'search_memory')]) assert.throws(()=>api.acceptDecision(s,read()));
 assert.throws(()=>api.acceptDecision(searched(),read(id)));
 const s=JSON.parse(api.acceptDecision(searched(),read())); assert.equal(s.status,'running');assert.equal(s.steps,2);assert.equal(s.pending.name,'read_conversation');
});
test('conversation read rejects forged fields, cursors and restored pending provenance',()=>{
 for(const arguments of [{id:hit,messageIndex:-1,offset:0},{id:hit,messageIndex:0,offset:1.5},{id:hit,messageIndex:0,offset:1000001},{id:hit,messageIndex:10000,offset:0},{id:'bad',messageIndex:0,offset:0},{id:hit,messageIndex:0,offset:0,approved:true}]) assert.throws(()=>api.acceptDecision(searched(),decision('read_conversation',arguments)));
 const s=JSON.parse(api.acceptDecision(searched(),read()));s.history[0].result='{"matches":[]}';assert.throws(()=>api.recover(JSON.stringify(s)));
});
test('read remains explicit durable read-only work with bounded existing step cap',()=>{
 let s=searched();for(let n=1;n<6;n++){s=api.acceptDecision(s,read());s=api.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result:'page'}));}
 assert.equal(JSON.parse(api.acceptDecision(s,read())).status,'failed');
 const pending=api.acceptDecision(searched(),read());assert.equal(JSON.parse(api.recover(pending)).status,'interrupted');assert.equal(JSON.parse(api.cancel(pending)).status,'cancelled');
 assert.match(api.prompt(searched()),/read_conversation/);
});

test('prompt discloses partial message pages and current-history semantics',()=>{const prompt=api.prompt(searched());assert.match(prompt,/messageTruncated or messageWindowLimited/);assert.match(prompt,/current saved message page, not an immutable snapshot/);});

test('search prompt constrains goal-derived words without quoted prose argument values',()=>{const prompt=api.prompt(searched());assert.doesNotMatch(prompt,/"query"\s*:\s*"1-256 UTF-8 bytes"/);assert.match(prompt,/query uses search words from USER_GOAL_JSON/);assert.match(prompt,/search_memory: same args, saved notes only/);assert.ok(Buffer.byteLength(prompt)<=3500);});
test('conversation-read prompt requires prior search and a returned UUID instead of a quoted placeholder',()=>{const prompt=api.prompt(searched());assert.match(prompt,/read_conversation: only after search; id is a returned UUID/);assert.doesNotMatch(prompt,/"id":"search hit ID"/);});
test('calculator documentation uses constraints instead of a quoted non-expression',()=>{const prompt=api.prompt(searched());assert.match(prompt,/expression is the exact requested arithmetic/);assert.doesNotMatch(prompt,/"expression":"1-256 UTF-8 bytes"/);});
