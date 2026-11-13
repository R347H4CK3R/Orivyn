const test=require('node:test'),assert=require('node:assert/strict');
let api;try{api=require('../../JarvisEVO/Resources/VMAssets/controller.js')}catch{}
const required=()=>{assert.ok(api,'Missing owner-safe VM controller');return api};
function fixture(load=async()=>({})){let made=0,destroyed=0,started=0,sent=[];let listener;const events=[];const vm={add_listener:(n,f)=>{if(n==='emulator-ready')listener=f},run:async()=>{started++},stop:async()=>{},destroy:async()=>{destroyed++},get_instruction_counter:()=>123,v86:{cpu:{devices:{}}},keyboard_send_text:async t=>sent.push(t)};return{events,vm,get made(){return made},get destroyed(){return destroyed},get started(){return started},sent,ready:()=>listener(),controller:required().createController({owner:'12345678-1234-1234-1234-123456789abc',load,construct:()=>{made++;return vm},emit:e=>events.push(e)})}}
test('missing owner rejected before VM construction',()=>assert.throws(()=>required().createController({owner:'x'})));
test('stop while assets load prevents construction and stale ready',async()=>{let release;const f=fixture(()=>new Promise(r=>release=r));const p=f.controller.start();const stopped=f.controller.stop();release({});await p;await stopped;assert.equal(f.made,0);assert.equal(f.events.at(-1).event,'stopped')});
test('one owner admits only one start and bounded input',async()=>{const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;await f.controller.start();assert.equal(f.made,1);assert.equal(f.started,1);await f.controller.type('hello');assert.deepEqual(f.sent,['hello']);await assert.rejects(f.controller.type('a'.repeat(1025)));await assert.rejects(f.controller.type('\u0000'));await f.controller.stop();assert.equal(f.destroyed,1);await assert.rejects(f.controller.type('late'))});
test('ready after stop cannot start VM',async()=>{const f=fixture();const p=f.controller.start();await Promise.resolve();const stop=f.controller.stop();f.ready();await p;await stop;assert.equal(f.started,0);assert.equal(f.destroyed,1);assert.equal(f.events.at(-1).event,'stopped')});
test('NIC invariant refuses engine before run',async()=>{const f=fixture();f.vm.v86.cpu.devices.net={};const p=f.controller.start();await Promise.resolve();f.ready();await p;assert.equal(f.started,0);assert.equal(f.events.at(-1).event,'error');assert.equal(f.destroyed,1)});
test('initialization failure is reported even when engine cleanup rejects',async()=>{const f=fixture();f.vm.add_listener=()=>{throw Error('init')};f.vm.destroy=async()=>{throw Error('cleanup')};await assert.doesNotReject(f.controller.start());assert.equal(f.events.at(-1).event,'error')});
test('controller failure preserves bounded reason before teardown',async()=>{const f=fixture();f.vm.add_listener=()=>{throw TypeError('native init '+ 'x'.repeat(1000))};await f.controller.start();const d=f.events.find(e=>e.event==='diagnostic');assert.ok(d,'initialization reason must survive error cleanup');assert.match(d.diagnostic,/TypeError: native init/);assert.ok(d.diagnostic.length<=256);assert.equal(d.instructions,0);assert.equal(f.events.at(-1).event,'error')});
test('checkpoint leaves VM paused and requires explicit resume',async()=>{const f=fixture();f.vm.stop=async()=>{};f.vm.save_state=async()=>new Uint8Array([1]).buffer;const p=f.controller.start();await Promise.resolve();f.ready();await p;let saved=false;global.OfflineVMCheckpoint={save:async(engine,bridge,identity,current)=>{assert.equal(current(),true);saved=true;await engine.stop();return{bytes:1}}};await f.controller.saveCheckpoint(async()=>{},{});assert.ok(saved);await assert.rejects(f.controller.type('paused'));await f.controller.resume();assert.equal(f.started,2);await f.controller.stop()});
test('stop invalidates in-flight snapshot and prevents resume',async()=>{const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;let release,valid;global.OfflineVMCheckpoint={save:async(engine,bridge,identity,current)=>{valid=current;await new Promise(r=>release=r);if(!current())throw Error('owner expired')}};const pending=f.controller.saveCheckpoint(async()=>{},{});await Promise.resolve();const stopped=f.controller.stop();assert.equal(valid(),false);assert.equal(f.destroyed,0);release();await assert.rejects(pending);await stopped;await assert.rejects(f.controller.resume());assert.equal(f.started,1)});
test('diagnostic console emits only fixed guest key chord',async()=>{
 const events=[];let ready;const machine={add_listener:(n,f)=>{ready=f},v86:{cpu:{devices:{}}},run:async()=>{},destroy:async()=>{},keyboard_send_scancodes:async codes=>events.push(codes),get_instruction_counter:()=>1};
 const c=required().createController({owner:'12345678-1234-1234-1234-123456789abc',emit:()=>{},load:async()=>({}),construct:()=>machine});
 const starting=c.start();await new Promise(r=>setImmediate(r));ready();await starting;
 await c.diagnosticConsole();assert.deepEqual(events,[[0x1d,0x38,0x3b,0xbb,0xb8,0x9d]]);await c.stop();await assert.rejects(()=>c.diagnosticConsole());
});
test('repeated stop waits for the same outstanding engine destruction',async()=>{
 const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;
 let finish;f.vm.destroy=()=>new Promise(r=>finish=r);
 const first=f.controller.stop();let secondDone=false;const second=f.controller.stop().then(()=>secondDone=true);
 await new Promise(r=>setImmediate(r));assert.equal(secondDone,false,'second caller must not release its lease before teardown');
 finish();await Promise.all([first,second]);assert.equal(f.events.filter(e=>e.event==='stopped').length,1);
});
test('checkpoint and concurrent input cannot race an outstanding key transfer',async()=>{
 const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;
 let finish;f.vm.keyboard_send_text=()=>new Promise(r=>finish=r);
 const typing=f.controller.type('slow');let saved=false;global.OfflineVMCheckpoint={save:async()=>{saved=true}};
 await assert.rejects(f.controller.saveCheckpoint(async()=>{},{}));assert.equal(saved,false);
 await assert.rejects(f.controller.type('overlap'));await assert.rejects(f.controller.diagnosticConsole());
 finish();await typing;await f.controller.saveCheckpoint(async()=>{},{});assert.equal(saved,true);await f.controller.stop();
});
test('resume owns transition before asynchronous engine run',async()=>{
 const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;
 global.OfflineVMCheckpoint={save:async()=>({})};await f.controller.saveCheckpoint(async()=>{},{});
 let calls=0,finish;f.vm.run=()=>{calls++;return new Promise(r=>finish=r)};
 const first=f.controller.resume();let secondError;const second=f.controller.resume().catch(e=>{secondError=e});
 await Promise.resolve();assert.equal(calls,1,'repeated Resume must not start another run');
 await assert.rejects(f.controller.saveCheckpoint(async()=>{},{}));
 finish();await Promise.all([first,second]);assert.match(secondError.message,/Invalid resume state/);await f.controller.stop();
});
test('failed resume reports error and cannot admit another checkpoint',async()=>{
 const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;
 global.OfflineVMCheckpoint={save:async()=>({})};await f.controller.saveCheckpoint(async()=>{},{});
 f.vm.run=async()=>{throw Error('run failed')};await assert.rejects(f.controller.resume(),/run failed/);
 assert.equal(f.events.at(-1).event,'error');await assert.rejects(f.controller.saveCheckpoint(async()=>{},{}));await f.controller.stop();
});
test('stop drains pending resume before destroying and announcing teardown',async()=>{
 const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;
 global.OfflineVMCheckpoint={save:async()=>({})};await f.controller.saveCheckpoint(async()=>{},{});
 let finish;f.vm.run=()=>new Promise(r=>finish=r);
 const resuming=f.controller.resume();const stopping=f.controller.stop();await Promise.resolve();
 assert.equal(f.destroyed,0,'do not destroy while engine resume is pending');
 finish();await Promise.all([resuming,stopping]);assert.equal(f.destroyed,1);
 assert.equal(f.events.at(-1).event,'stopped');
});
test('stop drains keyboard transfer before destroying and blocks new input',async()=>{
 const f=fixture();const p=f.controller.start();await Promise.resolve();f.ready();await p;
 let finish;f.vm.keyboard_send_text=()=>new Promise(r=>finish=r);
 const typing=f.controller.type('pending');const stopping=f.controller.stop();await Promise.resolve();
 assert.equal(f.destroyed,0,'outstanding keyboard work still owns engine');
 await assert.rejects(f.controller.type('late'));finish();await Promise.all([typing,stopping]);assert.equal(f.destroyed,1);
});
test('stop retains ownership until asset allocation finishes',async()=>{
 let finish;const f=fixture(()=>new Promise(r=>finish=r));const starting=f.controller.start();
 const stopping=f.controller.stop();await Promise.resolve();
 assert.equal(f.events.some(e=>e.event==='stopped'),false,'asset bytes can still be allocated');
 finish({});await Promise.all([starting,stopping]);assert.equal(f.made,0);assert.equal(f.events.at(-1).event,'stopped');
});
test('stop after startup failure waits for shared failure cleanup',async()=>{
 const f=fixture();f.vm.run=async()=>{throw Error('run failed')};
 let finish;f.vm.destroy=()=>new Promise(r=>finish=r);
 const starting=f.controller.start();await Promise.resolve();f.ready();
 while(!finish)await new Promise(r=>setImmediate(r));
 let finished=false;const stopping=f.controller.stop().then(()=>finished=true);
 await new Promise(r=>setImmediate(r));const premature=finished;
 finish();await Promise.all([starting,stopping]);
 assert.equal(premature,false,'failed startup cleanup still owns the engine');
});
test('failed startup destruction cannot be acknowledged as successful stop',async()=>{
 const f=fixture();f.vm.run=async()=>{throw Error('run failed')};f.vm.destroy=async()=>{throw Error('destroy failed')};
 const starting=f.controller.start();await Promise.resolve();f.ready();await starting;
 await assert.rejects(f.controller.stop(),/destroy failed/);
 assert.equal(f.events.some(e=>e.event==='stopped'),false);
});
