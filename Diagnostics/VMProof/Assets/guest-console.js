(function(root){'use strict';
function createConsole(){let pending='';return Object.freeze({push(byte){if(Number.isInteger(byte)&&(byte===10||byte===9||byte>=32&&byte<=126))pending=(pending+String.fromCharCode(byte)).slice(-192)},take(){const value=pending;pending='';return value}})}
root.createGuestConsole=createConsole;if(typeof module!=='undefined')module.exports={createConsole};
})(globalThis);
