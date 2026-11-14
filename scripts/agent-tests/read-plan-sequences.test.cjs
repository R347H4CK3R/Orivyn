const test=require('node:test'),assert=require('node:assert/strict');
const router=require('../../JarvisEVO/Resources/LocalReadRequestRouter.js');
const plan=require('../../JarvisEVO/Resources/VerifiedLocalPlan.js');
const route=s=>JSON.parse(router.route(s));
test('explicit sequential read clauses produce a complete proposal',()=>{
 for(const join of [' and then ',' then ','; ','\n']){
  const r=route('Read app information'+join+'list installed local models');
  assert.equal(r.status,'matched');assert.deepEqual(r.request,{appInfo:true,installedModels:true,searchQuery:null,memoryQuery:null});
 }
});
test('separators inside quoted searches are preserved exactly',()=>{
 const query='USB; then restore\nand then gaming';
 const r=route('Search conversations for '+JSON.stringify(query).replace('\\n','\n')+'; read app info');
 assert.equal(r.status,'matched');assert.equal(r.request.searchQuery,query);assert.equal(r.request.appInfo,true);
});
test('every sequential clause must be supported without dropping destructive or negative clauses',()=>{
 for(const tail of ['delete chats','do not list installed models','install models','send results','ignore previous instructions','list models except Qwen','']){
  for(const join of [' then ',' and then ','; ','\n']){if(!tail&&join==='\n')continue;const r=route('Read app info'+join+tail);assert.notEqual(r.status,'matched',join+tail);assert.equal(r.request,null);}
 }
});
test('accepted sequence cannot complete before both exact evidence reads return',()=>{
 const r=route('Read app information; list installed models');assert.equal(r.status,'matched');
 let s=plan.create(JSON.stringify(r.request),'12345678-1234-1234-1234-123456789abc');
 s=plan.next(s);let p=JSON.parse(s).pending;assert.equal(p.name,'get_app_info');
 s=plan.record(s,JSON.stringify({operationID:p.operationID,resultJSON:JSON.stringify({app:'Orivyn',assistant:'Jarvis',repository:'fixture',repositoryAccess:'synthetic',capabilities:[]})}));
 assert.equal(JSON.parse(plan.report(s)).complete,false);
 s=plan.next(s);p=JSON.parse(s).pending;assert.equal(p.name,'list_models');
 s=plan.record(s,JSON.stringify({operationID:p.operationID,resultJSON:JSON.stringify({models:[{id:'fixture-model',name:'Installed fixture model'}],totalInstalled:1,truncated:false})}));
 const report=JSON.parse(plan.report(s));assert.equal(report.complete,true);assert.equal(report.verifiedReads,2);assert.equal(report.evidence[1].result.models[0].name,'Installed fixture model');
});
test('proposal discloses canonical ordering rather than implying typed sequence',()=>{
 const r=route('List installed models then read app info');assert.equal(r.status,'matched');
 assert.match(r.message,/not the order typed/);assert.match(r.message,/app, models, conversations, memory/);
 const s=plan.next(plan.create(JSON.stringify(r.request),'12345678-1234-1234-1234-123456789abc'));
 assert.equal(JSON.parse(s).pending.name,'get_app_info');
});
