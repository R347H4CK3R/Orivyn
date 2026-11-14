import sys,ctypes as C,hashlib,json,time,importlib.util
from pathlib import Path
quality=Path(__file__).resolve().parent
if len(sys.argv)!=4: raise SystemExit('usage: run.py LIBRARY MODEL_DIRECTORY OUTPUT_JSON')
libpath=Path(sys.argv[1]).resolve()
model=Path(sys.argv[2]).resolve()
output_path=Path(sys.argv[3]).resolve()
sys.path.insert(0,str(quality))
import fixtures,score
class Request(C.Structure):
 _fields_=[('model',C.c_char_p),('projector',C.c_char_p),('rgb',C.POINTER(C.c_uint8)),('rgb_bytes',C.c_size_t),('width',C.c_uint32),('height',C.c_uint32),('question',C.c_char_p),('question_bytes',C.c_size_t),('context',C.c_uint32),('output_tokens',C.c_uint32)]
class Report(C.Structure):
 _fields_=[(x,C.c_int) for x in ('status','phase','tokens','positions','image_chunks','callback_count','live_resources')]
sys.path.insert(0,str(quality.parent))
from verify_pair import verify_file
manifest_path=model/'MODEL_PAIR.json'
if not manifest_path.exists(): manifest_path=quality.parent/'Linux/Evidence/production/MODEL_PAIR.json'
manifest=json.loads(manifest_path.read_text())
paths=[]
for e in manifest['artifacts']:
 p=model/e['file'];verify_file(p,e['size'],e['sha']);paths.append(str(p).encode())
print('BINARY_SHA256',hashlib.file_digest(open(libpath,'rb'),'sha256').hexdigest(),flush=True)
lib=C.CDLL(str(libpath));lib.ov_create.restype=C.c_void_p
lib.ov_destroy.argtypes=[C.c_void_p]
lib.ov_run.argtypes=[C.c_void_p,C.POINTER(Request),C.c_void_p,C.c_size_t,C.POINTER(Report)]
frozen=json.loads((quality/'FROZEN_CASES.json').read_text());assert json.loads(json.dumps(fixtures.manifest()))==frozen
rows=[]
for case in fixtures.CASES:
 pixels=fixtures.render(case);rgb=(C.c_uint8*len(pixels)).from_buffer_copy(pixels);q=case[2].encode()
 session=lib.ov_create();assert session
 request=Request(*paths,rgb,len(pixels),384,384,q,len(q),2048,128)
 report=Report();output=C.create_string_buffer(16384);start=time.monotonic()
 try: status=lib.ov_run(session,C.byref(request),output,len(output),C.byref(report))
 finally: lib.ov_destroy(session)
 row=dict(id=case[0],status=status,output=output.value.decode(),report={k:getattr(report,k) for k,_ in Report._fields_},closeAcknowledged=True,rgbSHA256=hashlib.sha256(pixels).hexdigest(),question=case[2],seconds=round(time.monotonic()-start,2))
 rows.append(row);print(json.dumps(row),flush=True)
scored=score.evaluate({'cases':rows})
document={'scope':'Linux diagnostic only; binary-to-source provenance requires separate build evidence','librarySHA256':hashlib.file_digest(open(libpath,'rb'),'sha256').hexdigest(),'modelManifest':manifest,'cases':rows,'score':scored}
output_path.parent.mkdir(parents=True,exist_ok=True)
output_path.write_text(json.dumps(document,indent=2)+'\n')
print(json.dumps(scored),flush=True)
raise SystemExit(0 if scored['passed'] else 1)
