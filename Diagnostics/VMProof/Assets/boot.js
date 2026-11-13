'use strict';
(function(){
 const owner=location.hash.slice(1);
 const report=value=>window.webkit.messageHandlers.vmStatus.postMessage(value);
 const removeDiagnostics=installVMDiagnostics(window,owner,report);
 const bounded=async(name,max)=>{const response=await fetch('orivyn-vm://bundle/'+name,{credentials:'omit',cache:'no-store'});if(!response.ok)throw Error('Asset unavailable');const bytes=await response.arrayBuffer();if(!bytes.byteLength||bytes.byteLength>max)throw Error('Asset bound');return bytes;};
 const guestConsole=createGuestConsole();
 const controller=OfflineVM.createController({owner,emit:report,load:async()=>({wasm:await bounded('v86.wasm',12*1024*1024),bios:await bounded('seabios.bin',1024*1024),vga:await bounded('vgabios.bin',1024*1024),disk:await bounded('maintained.img',135266304)}),construct:a=>{const machine=new V86({wasm_fn:imports=>instantiateOfflineWasm(a.wasm,()=>bounded('v86-fallback.wasm',12*1024*1024),imports,diagnostic=>report({version:1,owner,event:'diagnostic',instructions:0,diagnostic})),...guestOptions(a.disk),bios:{buffer:a.bios},vga_bios:{buffer:a.vga},screen_container:document.getElementById('screen'),net_device:{type:'none'},autostart:false,disable_speaker:true,log_level:0});machine.add_listener('serial0-output-byte',byte=>guestConsole.push(byte));return machine;}});
 const bridge=command=>window.webkit.messageHandlers.vmCheckpoint.postMessage({...command,owner});
 window.orivynSaveCheckpoint=()=>controller.saveCheckpoint(bridge,window.orivynCheckpointIdentity);
 window.orivynRestoreCheckpoint=()=>controller.restoreCheckpoint(bridge,window.orivynCheckpointIdentity);
 window.orivynResume=()=>controller.resume();
 window.orivynType=text=>controller.type(text);
 const interval=setInterval(()=>{controller.status();const text=guestConsole.take();if(text)report({version:1,owner,event:'diagnostic',instructions:0,diagnostic:'guest serial: '+text});},1000);
 window.orivynStop=()=>{clearInterval(interval);removeDiagnostics();return controller.stop();};
 document.addEventListener('visibilitychange',()=>{if(document.hidden)window.orivynStop();});
 controller.start();
})();
