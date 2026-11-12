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
 }catch(e){if(!valid)return;phase='failed';const old=vm;vm=null;if(old)await old.destroy();report('error');}}
 async function type(text){if(!valid||phase!=='running'||typeof text!=='string'||text.length>1024||/[^\x09\x0a\x20-\x7e]/.test(text))throw Error('Invalid input state');await vm.keyboard_send_text(text,10);}
 function status(){if(valid&&phase==='running')report('running');}
 return Object.freeze({start,stop,type,status});
}
const api={createController};if(typeof module!=='undefined')module.exports=api;root.OfflineVM=api;
})(globalThis);
