(function(root){'use strict';
function guestOptions(disk){
 if(!(disk instanceof ArrayBuffer)||disk.byteLength!==135266304)throw Error('Invalid maintained disk');
 return {memory_size:128*1024*1024,vga_memory_size:8*1024*1024,hda:{buffer:disk},boot_order:0x132,net_device:{type:'none'},autostart:false,disable_speaker:true,log_level:0};
}
root.guestOptions=guestOptions;if(typeof module!=='undefined')module.exports={guestOptions};
})(globalThis);
