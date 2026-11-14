(function(root){'use strict';
async function instantiateOfflineWasm(primary,loadFallback,imports,diagnose){
 const message=(stage,error)=>diagnose((stage+': '+String(error?.name||'Error')+': '+String(error?.message||'unknown')).slice(0,256));
 try{return (await WebAssembly.instantiate(primary,imports)).instance.exports}
 catch(error){message('primary WebAssembly',error)}
 try{return (await WebAssembly.instantiate(await loadFallback(),imports)).instance.exports}
 catch(error){message('fallback WebAssembly',error);throw error}
}
if(typeof module!=='undefined')module.exports={instantiateOfflineWasm};root.instantiateOfflineWasm=instantiateOfflineWasm;
})(globalThis);
