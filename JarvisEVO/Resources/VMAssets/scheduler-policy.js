'use strict';
// This isolated proof forbids workers in CSP. Select v86's existing timer
// scheduler before its capability probe; do not relax CSP or patch the vendor.
Object.defineProperty(globalThis,'Worker',{value:undefined,writable:false,configurable:false});
