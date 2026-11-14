#!/usr/bin/env python3
"""Operator-run provenance refresh from repository root. Uses reviewed publisher HTTPS sources.

Downloads the pinned b9049 runtime, verifies its digest before loading the C API,
then fetches only GGUF metadata prefixes. Not a full weight or inference check.
It rewrites the three evidence JSON files; review their diff before generating.
"""
import pathlib, json, urllib.request, hashlib, concurrent.futures, tarfile, ctypes, io, struct
root = pathlib.Path('.cache/catalog-reconstruction')
dest = pathlib.Path('docs/model-catalog')
root.mkdir(parents=True, exist_ok=True)
dest.mkdir(parents=True, exist_ok=True)
repos = [('ggml-org/Qwen3-1.7B-GGUF', 'daeb8e2d528a760970442092f6bf1e55c3b659eb', 'Qwen 3 · 1.7B', 'Reasoning', ['Q4_K_M']), ('Qwen/Qwen2.5-0.5B-Instruct-GGUF', '9217f5db79a29953eb74d5343926648285ec7e67', 'Qwen 2.5 · 0.5B', 'General chat', ['q4_k_m', 'q5_k_m']), ('HuggingFaceTB/SmolLM2-360M-Instruct-GGUF', '593b5a2e04c8f3e4ee880263f93e0bd2901ad47f', 'SmolLM2 · 360M', 'General chat', ['q8_0']), ('Qwen/Qwen3-0.6B-GGUF', '23749fefcc72300e3a2ad315e1317431b06b590a', 'Qwen 3 · 0.6B', 'Reasoning', ['q8_0']), ('Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF', 'ebb2015119c907b064c512bf053e945850b5875f', 'Qwen 2.5 Coder · 0.5B', 'Coding', ['q4_k_m']), ('Qwen/Qwen2.5-1.5B-Instruct-GGUF', '91cad51170dc346986eccefdc2dd33a9da36ead9', 'Qwen 2.5 · 1.5B', 'General chat', ['q4_k_m']), ('HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF', '2d4a76a30b4af41ecd395c35725ac11688d4cfe4', 'SmolLM2 · 1.7B', 'General chat', ['q4_k_m']), ('Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF', 'f86cb2c1fa58255f8052cc32aeede1b7482d4361', 'Qwen 2.5 Coder · 1.5B', 'Coding', ['q4_k_m']), ('Qwen/Qwen3-1.7B-GGUF', '90862c4b9d2787eaed51d12237eafdfe7c5f6077', 'Qwen 3 · 1.7B', 'Reasoning', ['q8_0'])]

def fetch(spec):
    repo, rev, base, purpose, quants = spec
    url = 'https://huggingface.co/api/models/' + repo + '/revision/' + rev + '?blobs=true'
    d = json.load(urllib.request.urlopen(url, timeout=60))
    assert d['sha'] == rev and d['cardData']['license'] == 'apache-2.0' and (d['gated'] is False)
    lp = next((f['rfilename'] for f in d['siblings'] if f['rfilename'].lower() in ['license', 'license.txt']), 'README.md')
    lu = 'https://huggingface.co/' + repo + '/resolve/' + rev + '/' + lp
    license_bytes = urllib.request.urlopen(lu, timeout=60).read()
    assert b'apache' in license_bytes.lower()
    lh = hashlib.sha256(license_bytes).hexdigest()
    source = {'repository': repo, 'revision': rev, 'apiURL': url, 'publisherLicense': d['cardData']['license'], 'gated': d['gated'], 'licenseURL': lu, 'licenseSHA256': lh, 'files': [{'fileName': f['rfilename'], 'byteCount': f['size'], 'sha256': f['lfs']['sha256']} for f in d['siblings'] if f['rfilename'].endswith('.gguf')]}
    models = []
    for quant in quants:
        f = next((f for f in source['files'] if f['fileName'].lower().endswith(quant.lower() + '.gguf')))
        size = f['byteCount']
        assert size <= 2000000000
        notes = {'General chat': 'Short everyday conversations. Small models can make mistakes.', 'Coding': 'Code explanations and drafts. Review and test generated code; no code execution.', 'Reasoning': 'May display thinking text and spend the short reply budget on reasoning. Experimental on iPhone.'}[purpose]
        models.append(dict(f, id=f['fileName'][:-5].lower(), name=base + ' · ' + quant.upper(), baseModel=base, family=base.split(' · ')[0], purpose=purpose, quantization=quant.upper(), recommendedRAMGB=4 if size < 800000000 else 6 if size < 1500000000 else 8, notes=notes, repository=repo, revision=rev, license='Apache-2.0', licensePath=lp, licenseSHA256=lh, publisherLicense='apache-2.0', gated=False, architecture='llama' if 'SmolLM' in repo else 'qwen3' if 'Qwen3-' in repo else 'qwen2'))
    return (source, models)
sources = []
models = []
for source, entries in concurrent.futures.ThreadPoolExecutor(max_workers=4).map(fetch, repos):
    sources.append(source)
    models.extend(entries)
    print('Verified publisher', source['repository'], flush=True)
(dest / 'catalog.json').write_text(json.dumps({'verifiedAt': '2026-11-12', 'status': 'Reconstructed candidate, not byte-identical to prior lost source', 'defaultModelID': 'qwen2.5-0.5b-instruct-q4_k_m', 'models': models}, ensure_ascii=False, indent=2) + '\n')
(dest / 'publisher-evidence.json').write_text(json.dumps({'verifiedAt': '2026-11-12', 'method': 'Fresh official pinned repository API and license/card reads during reconstruction', 'sources': sources}, indent=2) + '\n')
archive = root / 'llama-b9049-bin-ubuntu-x64.tar.gz'
url = 'https://github.com/ggml-org/llama.cpp/releases/download/b9049/' + archive.name
if not archive.exists():
    urllib.request.urlretrieve(url, archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest() == '4e6876036026cb7ae1a475ce4ddbddb5a2f666918589b16ef2323bde3cc3b65b'
with tarfile.open(archive) as t:
    t.extractall(root / 'runtime', filter='data')
lib = ctypes.CDLL(str((root / 'runtime/llama-b9049/libllama.so').resolve()))

class Message(ctypes.Structure):
    _fields_ = [('role', ctypes.c_char_p), ('content', ctypes.c_char_p)]
lib.llama_chat_apply_template.argtypes = [ctypes.c_char_p, ctypes.POINTER(Message), ctypes.c_size_t, ctypes.c_bool, ctypes.c_char_p, ctypes.c_int32]
lib.llama_chat_apply_template.restype = ctypes.c_int32
messages = (Message * 2)(Message(b'system', b'You are helpful.'), Message(b'user', b'Say hello.'))
probes = []
for model in models:
    url = 'https://huggingface.co/' + model['repository'] + '/resolve/' + model['revision'] + '/' + model['fileName']
    request = urllib.request.Request(url, headers={'Range': 'bytes=0-7999999'})
    with urllib.request.urlopen(request, timeout=60) as response:
        buf = response.read(8000000)
    data = io.BytesIO(buf)

    def n(fmt):
        return struct.unpack('<' + fmt, data.read(struct.calcsize(fmt)))[0]

    def string():
        return data.read(n('Q')).decode('utf8')

    def value(kind):
        if kind == 8:
            return string()
        if kind == 9:
            item = n('I')
            return [value(item) for _ in range(n('Q'))]
        return n({0: 'B', 1: 'b', 2: 'H', 3: 'h', 4: 'I', 5: 'i', 6: 'f', 7: '?', 10: 'Q', 11: 'q', 12: 'd'}[kind])
    assert data.read(4) == b'GGUF'
    version = n('I')
    tensors = n('Q')
    count = n('Q')
    metadata = {}
    for _ in range(count):
        key = string()
        metadata[key] = value(n('I'))
    template = metadata['tokenizer.chat_template']
    output = ctypes.create_string_buffer(10000)
    written = lib.llama_chat_apply_template(template.encode(), messages, 2, True, output, 10000)
    assert written > 0 and metadata['general.architecture'] == model['architecture']
    probes.append({'repository': model['repository'], 'revision': model['revision'], 'file': model['fileName'], 'ggufVersion': version, 'architecture': model['architecture'], 'templateSHA256': hashlib.sha256(template.encode()).hexdigest(), 'renderedPrompt': output.value.decode(), 'renderedBytes': written})
    (dest / 'template-evidence.json').write_text(json.dumps(probes, indent=2) + '\n')
    print('Template passed', model['id'], flush=True)
print('Verified', len(models), 'exact-file templates. No full-file inference claimed for this run.')
