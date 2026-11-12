'use strict';
(function(){
 const owner=location.hash.slice(1);
 const report=value=>window.webkit.messageHandlers.vmStatus.postMessage(value);
 const removeDiagnostics=installVMDiagnostics(window,owner,report);
 const bounded=async(name,max)=>{const response=await fetch('orivyn-vm://bundle/'+name,{credentials:'omit',cache:'no-store'});if(!response.ok)throw Error('Asset unavailable');const bytes=await response.arrayBuffer();if(!bytes.byteLength||bytes.byteLength>max)throw Error('Asset bound');return bytes;};
 const controller=OfflineVM.createController({owner,emit:report,load:async()=>({wasm:await bounded('v86.wasm',12*1024*1024),bios:await bounded('seabios.bin',1024*1024),vga:await bounded('vgabios.bin',1024*1024)}),construct:a=>new V86({wasm_fn:imports=>instantiateOfflineWasm(a.wasm,()=>bounded('v86-fallback.wasm',12*1024*1024),imports,diagnostic=>report({version:1,owner,event:'diagnostic',instructions:0,diagnostic})),memory_size:64*1024*1024,vga_memory_size:2*1024*1024,bios:{buffer:a.bios},vga_bios:{buffer:a.vga},screen_container:document.getElementById('screen'),net_device:{type:'none'},autostart:false,disable_speaker:true,log_level:0})});
 const interval=setInterval(()=>controller.status(),1000);
 window.orivynStop=()=>{clearInterval(interval);removeDiagnostics();return controller.stop();};
 document.addEventListener('visibilitychange',()=>{if(document.hidden)window.orivynStop();});
 controller.start();
})();
