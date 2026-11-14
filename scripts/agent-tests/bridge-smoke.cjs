'use strict';
// Explicit executable acceptance driver; no model, JSCore, or iOS claim.
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const [binary, corePath, directory] = process.argv.slice(2);
const core = require(path.resolve(corePath));
const id = '11111111-1111-4111-8111-111111111111';
let activeDirectory = directory;
let checks = 0;
function check(actual, expected) { assert.deepEqual(actual, expected); checks++; }
function swift(command, input, fail = false) {
  const r = spawnSync(binary, [command, activeDirectory, id], {input, encoding:'utf8', maxBuffer:262144, timeout:10000});
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
// Large native result remains durable, but cannot be split across fresh model
// contexts and then mislabeled as fully remembered evidence.
check(JSON.parse(state).status, 'failed');
check(JSON.parse(state).history[1].result, result);
assert.match(JSON.parse(state).error,/narrower task/); checks++;
assert.throws(()=>core.prompt(state)); checks++;
assert.throws(()=>tool(state,'read_result',{step:2,offset:0})); checks++;
swift('archive'); swift('load',undefined,true); swift('restore'); check(swift('load'),state);

// Independent fitting task exercises real storage/cursors and simultaneous facts.
activeDirectory = path.join(directory,'fitting-context');
state = persist(core.create('Inspect bounded local results', id));
for (const text of ['{"application":"Orivyn"}', 'Earlier and later facts both remain present']) {
 state = persist(tool(state,'get_app_info'));
 state = persist(core.recordResult(state, JSON.stringify({operationID:JSON.parse(state).pending.operationID,result:text})));
}
state = persist(tool(state,'read_result',{step:1,offset:0}));
const prompt = core.prompt(state);
check(Buffer.byteLength(prompt)<=3500,true);
const facts=JSON.parse(prompt.split('UNTRUSTED_RESULTS_JSON=')[1].split('\n')[0]);
check(facts.map(x=>x.result),['{"application":"Orivyn"}','Earlier and later facts both remain present']);
check(JSON.parse(state).steps,2);
state = persist(core.acceptDecision(state,JSON.stringify({type:'answer',text:'A model proposal from the complete fitting context.'})));
check(JSON.parse(core.recover(swift('load'))).status,'answered');
console.log(JSON.stringify({checks,resultBytes:Buffer.byteLength(result),retainedItems:value.matches.length,omittedItems:value.omittedItems,status:'passed',scope:'Swift storage/budget + Node reducer; no model or iOS execution'}));
