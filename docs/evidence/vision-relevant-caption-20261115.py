import sys,ctypes as C,hashlib,json,time,importlib.util
from pathlib import Path
root=Path('/workspace/scratch/8352eb8fe69c')
quality=root/'orivyn-vision-quality-next/Diagnostics/VisionProof/QualityV1'
sys.path.insert(0,str(quality))
import fixtures,score
sys.path.insert(0,str(root/'orivyn-capabilities-next/Diagnostics/VisionProof/Linux'))
from real_gate import Request,Report
from verify_pair import verify_file
model=root/'orivyn-vision-models-2b'
manifest=json.loads((model/'MODEL_PAIR.json').read_text())
paths=[]
for e in manifest['artifacts']:
 p=model/e['file'];verify_file(p,e['size'],e['sha']);paths.append(str(p).encode())
libpath=root/'orivyn-vision-next/Diagnostics/VisionProof/Linux/vision.so'
print('BINARY_SHA256',hashlib.file_digest(open(libpath,'rb'),'sha256').hexdigest(),flush=True)
lib=C.CDLL(str(libpath));lib.ov_create.restype=C.c_void_p
lib.ov_destroy.argtypes=[C.c_void_p]
lib.ov_run.argtypes=[C.c_void_p,C.POINTER(Request),C.c_void_p,C.c_size_t,C.POINTER(Report)]
frozen=json.loads((quality/'FROZEN_CASES.json').read_text());assert json.loads(json.dumps(fixtures.manifest()))==frozen
rows=[]
for case in fixtures.CASES:
 pixels=fixtures.render(case);rgb=(C.c_uint8*len(pixels)).from_buffer_copy(pixels);q=('In one short sentence, describe visible evidence needed for this question: '+case[2]+' Do not infer hidden details.').encode()
 session=lib.ov_create();assert session
 request=Request(*paths,rgb,len(pixels),384,384,q,len(q),2048,128)
 report=Report();output=C.create_string_buffer(16384);start=time.monotonic()
 try: status=lib.ov_run(session,C.byref(request),output,len(output),C.byref(report))
 finally: lib.ov_destroy(session)
 row=dict(id=case[0],status=status,output=output.value.decode(),report={k:getattr(report,k) for k,_ in Report._fields_},closeAcknowledged=True,rgbSHA256=hashlib.sha256(pixels).hexdigest(),question=q.decode(),originalQuestion=case[2],seconds=round(time.monotonic()-start,2))
 rows.append(row);print(json.dumps(row),flush=True)
print('ALL_RESULTS',json.dumps(rows),flush=True)
print('CAPTION_STAGE_ONLY: no answer accuracy claim',flush=True)
