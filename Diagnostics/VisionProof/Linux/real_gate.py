#!/usr/bin/env python3
"""Real C ABI, synthetic RGB only. Expected labels never enter model prompts.
Returns nonzero on quality failure and retains actual outputs/reports.
"""
import ctypes as C
import hashlib
import json
from pathlib import Path
import sys
import time
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_pair import verify_file

class Request(C.Structure):
    _fields_ = [('model', C.c_char_p), ('projector', C.c_char_p), ('rgb', C.POINTER(C.c_uint8)),
                ('rgb_bytes', C.c_size_t), ('width', C.c_uint32), ('height', C.c_uint32),
                ('question', C.c_char_p), ('question_bytes', C.c_size_t),
                ('context', C.c_uint32), ('output_tokens', C.c_uint32)]
class Report(C.Structure):
    _fields_ = [(x, C.c_int) for x in ('status','phase','tokens','positions','image_chunks','callback_count','live_resources')]

def main():
    libpath, modeldir, evidence = map(Path, sys.argv[1:])
    evidence.mkdir(parents=True, exist_ok=True)
    manifest_path = modeldir / 'MODEL_PAIR.json'
    if not manifest_path.exists(): manifest_path = Path(__file__).resolve().parents[1] / 'MODEL_PAIR.json'
    manifest = json.loads(manifest_path.read_text())
    paths=[]
    for entry in manifest['artifacts']:
        path = modeldir / entry['file']; verify_file(path, entry['size'], entry['sha']); paths.append(str(path).encode())
    lib=C.CDLL(str(libpath.resolve())); lib.ov_create.restype=C.c_void_p
    lib.ov_destroy.argtypes=[C.c_void_p]; lib.ov_test_cancel_at.argtypes=[C.c_void_p,C.c_int]
    lib.ov_run.argtypes=[C.c_void_p,C.POINTER(Request),C.c_void_p,C.c_size_t,C.POINTER(Report)]
    results=[]
    # Shape/color swaps expose stereotyped answers. Control is intentionally blank.
    cases=[('red_circle','red','circle'),('blue_circle','blue','circle'),
           ('red_square','red','square'),('blue_square','blue','square'),
           ('blank',None,None)]
    for name,color,shape in cases:
        image=Image.new('RGB',(384,384),'white'); draw=ImageDraw.Draw(image)
        if shape=='circle': draw.ellipse((72,72,312,312),fill=color)
        elif shape=='square': draw.rectangle((72,72,312,312),fill=color)
        image.save(evidence/f'{name}.png'); pixels=image.tobytes(); rgb=(C.c_uint8*len(pixels)).from_buffer_copy(pixels)
        q=b'Describe the image briefly.'
        for phase in ([None,1,3,5] if name=='red_circle' else [None]):
            session=lib.ov_create(); assert session
            if phase is not None:lib.ov_test_cancel_at(session,phase)
            request=Request(*paths,rgb,len(pixels),384,384,q,len(q),2048,128)
            report=Report(); output=C.create_string_buffer(16384); start=time.monotonic()
            try: status=lib.ov_run(session,C.byref(request),output,len(output),C.byref(report))
            finally: lib.ov_destroy(session)
            text=output.value.decode('utf8'); lower=text.lower()
            if phase is None:
                quality=(color in lower and shape in lower) if color else (any(t in lower for t in ('blank','plain white','white background','white image')) and not any(t in lower for t in ('circle','square','person','man','woman','dog','cat','text','black')))
                passed=(status==10 and not text and report.positions==0 and report.live_resources==0) if name=="blank" else (status==0 and report.image_chunks==1 and report.live_resources==0 and quality)
            else: passed=status==2 and not text and report.live_resources==0 and report.phase==phase
            results.append(dict(fixture=name,cancel_phase=phase,status=status,output=text,
                report={k:getattr(report,k) for k,_ in Report._fields_},seconds=round(time.monotonic()-start,3),
                rgb_sha256=hashlib.sha256(pixels).hexdigest(),passed=passed))
            (evidence/'results.json').write_text(json.dumps({'scope':'Linux CPU real pinned mtmd; not iOS/device or broad vision acceptance','cases':results},indent=2)+'\n')
            print(name,phase,status,repr(text),passed,flush=True)
    return 0 if all(r['passed'] for r in results) else 1
if __name__=='__main__':sys.exit(main())
