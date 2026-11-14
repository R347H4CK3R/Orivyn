const test=require('node:test'),assert=require('node:assert/strict');
const api=require('../../JarvisEVO/Resources/LocalAgentCore.js');
const id='12345678-1234-1234-1234-123456789abc',hit='abcdefab-1234-1234-1234-123456789abc';
const start=()=>api.create('Find a saved note',id);
function record(s,name,result){s=api.acceptDecision(s,JSON.stringify({type:'tool',name,arguments:name==='get_app_info'?{}:{query:'note',limit:1}}));return api.recordResult(s,JSON.stringify({operationID:JSON.parse(s).pending.operationID,result}));}
test('fresh state advertises no conversation read or IDs',()=>{assert.deepEqual(JSON.parse(api.conversationIDs(start())),[]);assert.ok(!api.prompt(start()).includes('; read_conversation:'));});
test('only successful search UUIDs enable read advertisement',()=>{let s=record(start(),'search_conversations',JSON.stringify({matches:[{id:hit.toUpperCase()},{id:hit},{id:'invented'}]}));assert.deepEqual(JSON.parse(api.conversationIDs(s)),[hit]);assert.ok(api.prompt(s).includes('; read_conversation:'));});
test('unrelated and malformed results cannot mint capabilities',()=>{for(const [name,result] of [['get_app_info',JSON.stringify({matches:[{id:hit}]})],['search_memory',JSON.stringify({matches:[{id:hit}]})],['search_conversations','bad JSON'],['search_conversations','{"matches":[]}']]) assert.deepEqual(JSON.parse(api.conversationIDs(record(start(),name,result))),[]);});
test('invalid and nonready state fail closed',()=>{assert.throws(()=>api.conversationIDs('{}'));let s=api.acceptDecision(start(),JSON.stringify({type:'tool',name:'get_app_info',arguments:{}}));assert.throws(()=>api.conversationIDs(s));s=api.recover(s);assert.throws(()=>api.conversationIDs(s));});
