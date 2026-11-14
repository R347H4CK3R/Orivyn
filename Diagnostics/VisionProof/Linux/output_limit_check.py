#!/usr/bin/env python3
import ctypes as C
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw
from real_gate import Request,Report,verify_file
libpath,root=map(Path,sys.argv[1:]);paths=[]
for a in json.loads((root/'MODEL_PAIR.json').read_text())['artifacts']:
 p=root/a['file'];verify_file(p,a['size'],a['sha']);paths.append(str(p).encode())
lib=C.CDLL(str(libpath.resolve()));lib.ov_create.restype=C.c_void_p;lib.ov_destroy.argtypes=[C.c_void_p]
lib.ov_run.argtypes=[C.c_void_p,C.POINTER(Request),C.c_void_p,C.c_size_t,C.POINTER(Report)]
im=Image.new('RGB',(384,384),'white');ImageDraw.Draw(im).rectangle((72,72,312,312),fill='red')
b=im.tobytes();rgb=(C.c_uint8*len(b)).from_buffer_copy(b);q=b'Describe the visible image in one sentence.'
r=Request(*paths,rgb,len(b),384,384,q,len(q),2048,1);out=C.create_string_buffer(16384);report=Report();s=lib.ov_create()
try:status=lib.ov_run(s,C.byref(r),out,len(out),C.byref(report))
finally:lib.ov_destroy(s)
assert status==8 and not out.value and report.tokens==1 and report.live_resources==0
print(json.dumps(dict(status=status,output=out.value.decode(),tokens=report.tokens,live_resources=report.live_resources,passed=True)))
