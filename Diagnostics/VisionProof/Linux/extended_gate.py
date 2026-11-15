#!/usr/bin/env python3
"""Pinned stronger-pair comparison; actual outputs retained, no label leakage."""
import ctypes as C
import hashlib,json,sys,time
from pathlib import Path
from PIL import Image, ImageDraw
from real_gate import Request,Report,verify_file
libpath,modeldir,natural,evidence=map(Path,sys.argv[1:]);evidence.mkdir(parents=True,exist_ok=True)
manifest=json.loads((modeldir/'MODEL_PAIR.json').read_text());paths=[]
for e in manifest['artifacts']:
 p=modeldir/e['file'];verify_file(p,e['size'],e['sha']);paths.append(str(p).encode())
lib=C.CDLL(str(libpath.resolve()));lib.ov_create.restype=C.c_void_p
lib.ov_destroy.argtypes=[C.c_void_p];lib.ov_run.argtypes=[C.c_void_p,C.POINTER(Request),C.c_void_p,C.c_size_t,C.POINTER(Report)]
cases=[]
for color in ['red','blue']:
 for shape in ['circle','square']:
  im=Image.new('RGB',(384,384),'white');d=ImageDraw.Draw(im)
  (d.ellipse if shape=='circle' else d.rectangle)((72,72,312,312),fill=color)
  cases.append((color+'_'+shape,im,'Describe the visible image in one sentence.',[color,shape]))
for reverse in [False,True]:
 im=Image.new('RGB',(384,384),'white');d=ImageDraw.Draw(im)
 a,b=(230,30) if reverse else (30,230)
 d.ellipse((a,142,a+100,242),fill='red');d.rectangle((b,142,b+100,242),fill='blue')
 cases.append(('spatial_reverse' if reverse else 'spatial',im,'Where is the circle relative to the square? Answer in one sentence.',['right' if reverse else 'left']))
im=Image.new('RGB',(384,384),'white');d=ImageDraw.Draw(im)
for x in [30,145,260]:d.ellipse((x,145,x+80,225),fill='red')
cases.append(('count',im,'How many circles are visible? Answer briefly.',['three|3']))
im=Image.open(natural).convert('RGB');im.thumbnail((512,512))
cases.append(('natural_landscape',im,'Describe the visible scene in one sentence.',['mountain|cliff','water|river|lake']))
cases.append(('blank',Image.new('RGB',(384,384),'white'),'Describe the visible image in one sentence.',[]))
rows=[]
for name,im,q,expected in cases:
 pixels=im.tobytes();rgb=(C.c_uint8*len(pixels)).from_buffer_copy(pixels);q=q.encode();out=C.create_string_buffer(16384);report=Report()
 req=Request(*paths,rgb,len(pixels),im.width,im.height,q,len(q),2048,128);session=lib.ov_create();start=time.monotonic()
 try:status=lib.ov_run(session,C.byref(req),out,len(out),C.byref(report))
 finally:lib.ov_destroy(session)
 text=out.value.decode();passed=(status==10 and not text and report.positions==0) if name=='blank' else (status==0 and all(any(v in text.lower() for v in group.split('|')) for group in expected))
 rows.append(dict(fixture=name,question=q.decode(),output=text,status=status,passed=passed,rgb_sha256=hashlib.sha256(pixels).hexdigest(),seconds=round(time.monotonic()-start,3),report={k:getattr(report,k) for k,_ in Report._fields_}))
 (evidence/'results.json').write_text(json.dumps(dict(scope='Linux CPU, real C bridge; limited diagnostic, not general-vision or iOS acceptance',model=manifest,cases=rows),indent=2)+'\n');im.save(evidence/(name+'.png'))
 print(name,status,passed,repr(text),flush=True)
sys.exit(0 if all(r['passed'] and r['report']['live_resources']==0 for r in rows) else 1)
