const {test}=require('node:test');const assert=require('node:assert/strict');
const {guestOptions}=require('../../JarvisEVO/Resources/VMAssets/guest-profile.js');
test('maintained guest requires exact disk length and disables external runtime',()=>{
 assert.throws(()=>guestOptions(new ArrayBuffer(1)),/disk/);
 const disk=new ArrayBuffer(135266304);const o=guestOptions(disk);
 assert.equal(o.hda.buffer,disk);assert.equal(o.memory_size,128*1024*1024);
 assert.equal(o.vga_memory_size,8*1024*1024);assert.equal(o.net_device.type,'none');
 assert.equal(o.autostart,false);assert.equal(o.network_relay_url,undefined);
 assert.equal(o.filesystem,undefined);assert.equal(o.boot_order,0x132);
});
