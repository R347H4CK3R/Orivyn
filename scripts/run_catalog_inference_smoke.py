#!/usr/bin/env python3
"""Use the exact engine compiler/runner with a catalog-specific driver. No downloads."""
import hashlib,json,pathlib,sys
import run_llama_engine_smoke as engine

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1048576),b''):h.update(chunk)
 return {'file':path.name,'bytes':path.stat().st_size,'sha256':h.hexdigest()}

def main():
 # The base runner parses and validates the same explicit local arguments.
 engine.SOURCES = [x for x in engine.SOURCES if x != 'scripts/swift-smoke/LlamaEngineSmoke.swift'] + ['scripts/swift-smoke/CatalogInferenceSmoke.swift']
 code=engine.main()
 model=pathlib.Path(sys.argv[sys.argv.index('--model')+1])
 out=pathlib.Path(sys.argv[sys.argv.index('--output')+1])
 (out/'CATALOG-MODELS-MANIFEST.json').write_text(json.dumps([digest(x) for x in sorted(model.parent.glob('*.gguf'))],indent=2)+'\n')
 return code
if __name__=='__main__':raise SystemExit(main())
