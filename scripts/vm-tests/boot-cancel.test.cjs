const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
test('pre-bootstrap cancellation prevents any guest setup or asset acquisition',async()=>{
 const window={orivynBootCancelled:true};
 // No guest dependencies are provided: a canceled bootstrap must not touch them.
 const sandbox={window,Promise};
 assert.doesNotThrow(()=>vm.runInNewContext(fs.readFileSync(require.resolve('../../JarvisEVO/Resources/VMAssets/boot.js'),'utf8'),sandbox));
 assert.equal(typeof window.orivynStop,'function');
 await window.orivynStop();
});
