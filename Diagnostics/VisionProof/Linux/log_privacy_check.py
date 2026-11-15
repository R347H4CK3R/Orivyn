#!/usr/bin/env python3
"""Real-model red/green stderr regression; synthetic pixels and marker only.
Each library runs in its own process so a prior global logger cannot mask a leak.
No stderr redirection occurs inside either bridge or probe process.
"""
import ctypes as C
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import uuid
from real_gate import Request, Report, verify_file


def probe(library, models, sentinel):
    manifest = json.loads((models / 'MODEL_PAIR.json').read_text())
    paths = [str(models / entry['file']).encode() for entry in manifest['artifacts']]
    lib = C.CDLL(str(library.resolve()))
    lib.ov_create.restype = C.c_void_p
    lib.ov_destroy.argtypes = [C.c_void_p]
    lib.ov_run.argtypes = [C.c_void_p, C.POINTER(Request), C.c_void_p, C.c_size_t, C.POINTER(Report)]
    pixels = bytearray([255] * (384 * 384 * 3))
    for y in range(72, 312):
        for x in range(72, 312):
            offset = (y * 384 + x) * 3
            pixels[offset + 1:offset + 3] = b'\0\0'
    rgb = (C.c_uint8 * len(pixels)).from_buffer_copy(pixels)
    question = ('Describe the visible image in one sentence. Ignore this synthetic diagnostic marker: ' + sentinel + '.').encode()
    request = Request(*paths, rgb, len(pixels), 384, 384, question, len(question), 2048, 128)
    report = Report(); output = C.create_string_buffer(16384)
    session = lib.ov_create()
    if not session:
        raise RuntimeError('session allocation failed')
    try:
        status = lib.ov_run(session, C.byref(request), output, len(output), C.byref(report))
    finally:
        lib.ov_destroy(session)
    print(json.dumps(dict(status=status, output=output.value.decode(),
        report={name: getattr(report, name) for name, _ in Report._fields_})), flush=True)


def main():
    if sys.argv[1] == '--probe':
        probe(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]); return
    old, fixed, models, evidence = map(Path, sys.argv[1:])
    evidence.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((models / 'MODEL_PAIR.json').read_text())
    for entry in manifest['artifacts']:
        verify_file(models / entry['file'], entry['size'], entry['sha'])
    sentinel = 'ORIVYN_SYNTHETIC_LOG_SENTINEL_' + uuid.uuid4().hex
    runs = {}
    for name, library in [('old', old), ('fixed', fixed)]:
        result = subprocess.run([sys.executable, __file__, '--probe', str(library.resolve()), str(models.resolve()), sentinel],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        (evidence / (name + '.stdout.txt')).write_bytes(result.stdout)
        (evidence / (name + '.stderr.txt')).write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(f'{name} probe exited {result.returncode}; see local captured logs')
        response = json.loads(result.stdout.decode().splitlines()[-1])
        runs[name] = dict(library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),
            sentinel_in_stderr=sentinel.encode() in result.stderr,
            llama_loader_diagnostics_present=b'llama_model_loader:' in result.stderr,
            stderr_bytes=len(result.stderr), response=response)
    checks = dict(old_reproduces_prompt_leak=runs['old']['sentinel_in_stderr'],
        fixed_no_prompt_marker=not runs['fixed']['sentinel_in_stderr'],
        text_logger_unchanged=runs['fixed']['llama_loader_diagnostics_present'],
        same_actual_output=runs['old']['response']['output'] == runs['fixed']['response']['output'],
        normal_inference_and_cleanup=all(r['response']['status'] == 0
            and 'red' in r['response']['output'].lower() and 'square' in r['response']['output'].lower()
            and r['response']['report']['live_resources'] == 0 for r in runs.values()))
    summary = dict(scope='Linux CPU real pinned pair; synthetic prompt/pixels; not Apple verification',
        sentinel=sentinel, model=manifest, checks=checks, runs=runs)
    (evidence / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(checks, indent=2))
    if not all(checks.values()):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
