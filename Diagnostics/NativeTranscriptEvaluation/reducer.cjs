'use strict';
const fs=require('fs'),core=require('../../JarvisEVO/Resources/LocalAgentCore.js');
const input=JSON.parse(fs.readFileSync(0,'utf8'));
if(!['create','createReviewed','decisionPolicy','prompt','acceptDecision','recordResult','conversationIDs'].includes(input.method)||!Array.isArray(input.args))throw Error('Unknown diagnostic reducer method');
process.stdout.write(JSON.stringify(core[input.method](...input.args)));
