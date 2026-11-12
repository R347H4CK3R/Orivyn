#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo "Native Apple build requires macOS"; exit 1; }
ROOT="$1"
EVIDENCE="$2"
SOURCE="$ROOT/.cache/vision-runtime/llama-b9049"
cd "$ROOT"

 set -euo pipefail
 mkdir -p "$(dirname "$SOURCE")"
 if [[ ! -d "$SOURCE/.git" ]]; then
  git clone --depth 1 --branch b9049 https://github.com/ggml-org/llama.cpp.git "$SOURCE"
 fi
 [[ "$(git -C "$SOURCE" rev-parse HEAD)" == 2496f9c14965c39589f53eea31bdb6d762b1d360 ]]
 python3 - "$SOURCE" <<'PY'
from pathlib import Path
import json,hashlib,sys
root=Path(sys.argv[1]);manifest=json.loads(Path('Diagnostics/VisionRuntime/source-integrity.json').read_text())
for f in manifest['files']:
 b=(root/f['path']).read_bytes()
 if len(b)!=f['bytes'] or hashlib.sha256(b).hexdigest()!=f['sha256']:raise ValueError('Pinned source mismatch: '+f['path'])
print('All reviewed source hashes match exact b9049 checkout')
PY
 cd "$SOURCE"
 bash "$ROOT/Diagnostics/VisionRuntime/build-ios-mtmd.sh"
 for slice in build-ios-sim build-ios-device; do
  binary="$slice/framework/llama.framework/llama"
  xcrun lipo -archs "$binary"
  xcrun nm -arch arm64 -gU "$binary" > "$EVIDENCE/$slice-symbols.txt"
  for symbol in _llama_backend_init _mtmd_init_from_file _mtmd_helper_eval_chunk_single; do
   [[ $(grep -Ec "[[:space:]]${symbol}$" "$EVIDENCE/$slice-symbols.txt") == 1 ]]
  done
 done
 mkdir -p "$ROOT/Diagnostics/VisionProof/Frameworks"
 cp -R build-apple/llama.xcframework "$ROOT/Diagnostics/VisionProof/Frameworks/"
 # Cacheable private development artifact, not an IPA/public release asset.
 ditto -c -k --keepParent build-apple/llama.xcframework "$EVIDENCE/llama-mtmd-b9049.xcframework.zip"
 shasum -a 256 "$EVIDENCE/llama-mtmd-b9049.xcframework.zip" > "$EVIDENCE/framework-sha256.txt"
