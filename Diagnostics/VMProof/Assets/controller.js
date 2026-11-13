(function(root){'use strict';
function createController({owner,load,construct,emit}){
 if(!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(owner))throw Error('Invalid owner');
 let valid=true,phase='idle',vm=null,finishReady=null,timer=null;
 const report=event=>emit({version:1,owner,event,instructions:Math.max(0,Math.min(Number.MAX_SAFE_INTEGER,Math.floor(vm?.get_instruction_counter?.()||0)))});
 async function stop(){if(!valid)return;valid=false;phase='stopped';clearTimeout(timer);finishReady?.();finishReady=null;const old=vm;vm=null;if(old)await old.destroy();report('stopped');}
 async function start(){if(!valid||phase!=='idle')return;phase='preparing';try{
  const assets=await load();if(!valid)return;
  vm=construct(assets);
  await new Promise((resolve,reject)=>{finishReady=resolve;timer=setTimeout(()=>reject(Error('Initialization deadline')),20000);vm.add_listener('emulator-ready',resolve)});
  clearTimeout(timer);finishReady=null;if(!valid)return;
  if(vm.v86.cpu.devices.net||vm.v86.cpu.devices.virtio_net||vm.network_adapter)throw Error('Offline invariant');
  report('ready');await vm.run();if(!valid)return;phase='running';report('running');
 }catch(e){if(!valid)return;emit({version:1,owner,event:'diagnostic',instructions:0,diagnostic:('controller: '+String(e?.name||'Error')+': '+String(e?.message||'unknown')).slice(0,256)});phase='failed';clearTimeout(timer);finishReady=null;const old=vm;vm=null;report('error');if(old){try{await old.destroy()}catch{ /* Failure remains reported; never convert cleanup failure to success. */ }}}}
 async function type(text){if(!valid||phase!=='running'||typeof text!=='string'||text.length>1024||/[^\x09\x0a\x20-\x7e]/.test(text))throw Error('Invalid input state');await vm.keyboard_send_text(text,10);}
 async function diagnosticConsole(){if(!valid||phase!=='running')throw Error('Invalid input state');await vm.keyboard_send_scancodes([0x1d,0x38,0x3b,0xbb,0xb8,0x9d],30);}
 async function checkpoint(action,bridge,identity){if(!valid||!['running','paused'].includes(phase))throw Error('Invalid checkpoint state');const target=vm;phase='checkpoint';let stopped=false;try{await target.stop();stopped=true;return await root.OfflineVMCheckpoint[action](target,bridge,identity,()=>valid&&vm===target)}finally{if(valid&&vm===target){phase=stopped?'paused':'failed';report(stopped?'paused':'error')}}}
 async function resume(){if(!valid||phase!=='paused')throw Error('Invalid resume state');await vm.run();if(!valid)return;phase='running';report('running')}
 function status(){if(valid&&phase==='running')report('running');}
 return Object.freeze({start,stop,type,status,resume,diagnosticConsole,saveCheckpoint:(bridge,identity)=>checkpoint('save',bridge,identity),restoreCheckpoint:(bridge,identity)=>checkpoint('restore',bridge,identity)});
}
const api={createController};if(typeof module!=='undefined')module.exports=api;root.OfflineVM=api;
})(globalThis);
(function(root){'use strict';root.installVMDiagnostics=function(target,owner,emit){let active=true;const report=(stage,error)=>{if(active)emit({version:1,owner,event:'diagnostic',instructions:0,diagnostic:(stage+': '+String(error?.name||'Error')+': '+String(error?.message||'unknown')).slice(0,256)})};const rejection=e=>report('engine promise',e.reason),error=e=>report('engine script',e.error||{message:e.message});target.addEventListener('unhandledrejection',rejection);target.addEventListener('error',error);return()=>{active=false;target.removeEventListener('unhandledrejection',rejection);target.removeEventListener('error',error)}}})(globalThis);
