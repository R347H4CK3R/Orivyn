'use strict';
const fs=require('node:fs');
const core=require('./LocalAgentCore.js');
const input=JSON.parse(fs.readFileSync(0,'utf8'));
if(!['create','prompt','acceptDecision','recordResult','fail'].includes(input.method)||!Array.isArray(input.args))throw Error('Invalid test driver operation');
process.stdout.write(JSON.stringify(core[input.method](...input.args)));
