const {test}=require('node:test');const assert=require('node:assert/strict');
const {createConsole}=require('../Assets/guest-console.js');
test('guest serial display is bounded inert text and rejects noncharacters',()=>{
 const c=createConsole();c.push(1000);c.push({command:'execute'});assert.equal(c.take(),'');
 for(const x of 'ok\x1b[31m\n')c.push(x.charCodeAt(0));assert.equal(c.take(),'ok[31m\n');
 for(let i=0;i<3000;i++)c.push(65);assert.equal(c.take().length,192);assert.equal(c.take(),'');
});
