"""Compile exact production portable sources + isolated CLI; no model execution."""
import hashlib,json,pathlib,runpy,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[2];out=pathlib.Path(sys.argv[1]).resolve();out.mkdir(parents=True,exist_ok=True)
sources=runpy.run_path(str(root/'scripts/run_foundation_tests.py'))['SOURCES']+[
 'JarvisEVO/Core/NativeToolTranscript.swift','JarvisEVO/Core/NativeToolResponseAdapter.swift',
 'Diagnostics/NativeTranscriptEvaluation/NativeTranscriptCLI.swift']
(out/'swift-source-manifest.json').write_text(json.dumps([{'path':p,'sha256':hashlib.sha256((root/p).read_bytes()).hexdigest()} for p in sources],indent=2))
with (out/'swift-build.log').open('w') as log:
 result=subprocess.run(['swiftc','-swift-version','6','-strict-concurrency=complete','-parse-as-library',*[str(root/p) for p in sources],'-o',str(out/'native-transcript-cli')],stdout=log,stderr=subprocess.STDOUT)
if result.returncode:
 print((out/'swift-build.log').read_text());raise SystemExit(result.returncode)
print('Compiled actual Swift builder/adapter CLI; model/engine evaluation remains separate')
