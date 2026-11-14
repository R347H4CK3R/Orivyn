'use strict';
// Explicit executable acceptance driver; no model, JSCore, or iOS claim.
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const [binary, corePath, directory] = process.argv.slice(2);
const core = require(path.resolve(corePath));
const id = '11111111-1111-4111-8111-111111111111';
let checks = 0;
function check(actual, expected) { assert.deepEqual(actual, expected); checks++; }
function swift(command, input, fail = false) {
  const r = spawnSync(binary, [command, directory, id], {input, encoding:'utf8', maxBuffer:262144, timeout:10000});
  if (r.error) throw r.error;
  if (fail) { assert.equal(r.status, 1); assert.match(r.stderr,/^bridge-rejected:/); checks+=2; return; }
  assert.equal(r.status, 0, r.stderr); return r.stdout;
}
function persist(state) { swift('save', state); const raw = swift('load'); check(raw, state); return raw; }
function tool(state, name, args={}) { return core.acceptDecision(state, JSON.stringify({type:'tool',name,arguments:args})); }
let state = persist(core.create('Inspect local results', id));
state = persist(tool(state, 'search_conversations', {query:'界',limit:10}));
check(JSON.parse(state).status, 'running');
// Separate process reopens the record: dispatch cannot silently repeat after interruption.
state = persist(core.recover(swift('load')));
check(JSON.parse(state).status, 'interrupted');
assert.throws(()=>tool(state,'get_app_info')); checks++;
state = persist(core.resume(state));
check(JSON.parse(state).history[0].outcome, 'interrupted');
state = persist(tool(state, 'search_conversations', {query:'界',limit:10}));
const result = swift('result');
check(Buffer.byteLength(result)<=4096, true);
const value = JSON.parse(result);
check(value.resultTruncated, true);
check(value.matches.length > 0 && value.matches.length < 10, true);
for (const row of value.matches) {
 check(row.title, '\n'.repeat(96));
 check(row.excerpt, '界😀\t'.repeat(20));
}
check(value.matches.length + value.omittedItems, 10);
check(value.matches.map(x=>x.id), Array.from({length:value.matches.length},(_,i)=>i));
const running = state;
state = persist(core.recordResult(state, JSON.stringify({operationID:JSON.parse(state).pending.operationID,result})));
// Old completions cannot settle again, nor roll back the durable revision.
assert.throws(()=>core.recordResult(state,JSON.stringify({operationID:id+':1',result}))); checks++;
swift('save', running, true);
check(swift('load'), state);
// A later successful tool result must not hide prior search data.
state = persist(tool(state, 'get_app_info'));
state = persist(core.recordResult(state, JSON.stringify({operationID:JSON.parse(state).pending.operationID,result:'{"application":"Orivyn"}'})));
state = persist(tool(state,'read_result',{step:2,offset:0}));
// Read every UTF-8 page through the production prompt and reducer, preserving exact bytes.
let pages = '', pageCount = 0;
for (;;) {
 assert.ok(++pageCount<=20, 'bounded paging must terminate');
 const prompt = core.prompt(state);
 const line = prompt.split('\n').find(x=>x.startsWith('UNTRUSTED_PAGE_JSON='));
 const page = JSON.parse(line.slice('UNTRUSTED_PAGE_JSON='.length));
 check(Buffer.byteLength(page.text)<=256, true);
 pages += page.text;
 if (page.endOfResult) break;
 state = persist(tool(state,'read_result',{step:2,offset:page.nextOffset}));
}
check(pages, result);
check(JSON.parse(state).steps, 3);
// Archive/restore must preserve the entire paged task record byte-for-byte.
swift('archive'); swift('load',undefined,true); swift('restore'); check(swift('load'),state);
state = persist(core.acceptDecision(state,JSON.stringify({type:'answer',text:'Partial local results; omitted items remain unavailable.'})));
check(JSON.parse(core.recover(swift('load'))).status,'answered');
console.log(JSON.stringify({checks, resultBytes:Buffer.byteLength(result), retainedItems:value.matches.length, omittedItems:value.omittedItems, status:'passed', scope:'Swift storage/budget + Node reducer; no model or iOS execution'}));
