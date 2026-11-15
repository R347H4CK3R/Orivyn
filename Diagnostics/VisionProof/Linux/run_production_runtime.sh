#!/usr/bin/env bash
set -euo pipefail
SWIFTC="${1:?Swift compiler}"; LIB="${2:?absolute real vision shared library}"; MODELS="${3:?verified pair directory}"; OUT="${4:?absolute output directory}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
mkdir -p "$OUT/module"
python3 - "$ROOT" "$OUT/module/module.modulemap" "$MODELS" <<'PY'
import sys,json
from pathlib import Path
root,output,models=map(Path,sys.argv[1:])
sys.path.insert(0,str(root/'Diagnostics/VisionProof'))
from verify_pair import verify_file
for a in json.loads((models/'MODEL_PAIR.json').read_text())['artifacts']:
 verify_file(models/a['file'],a['size'],a['sha'])
output.write_text('module llama { header '+json.dumps(str(root/'Diagnostics/VisionProof/Bridge/vision_bridge.h'))+' export * }\n')
PY
"$SWIFTC" -static-stdlib -swift-version 6 -strict-concurrency=complete -D ORIVYN_NATIVE_VISION -I "$OUT/module" \
 "$ROOT/JarvisEVO/Core/LocalHeavyWork.swift" "$ROOT/JarvisEVO/Core/VisionSession.swift" \
 "$ROOT/JarvisEVO/Core/VisionPixelBoundary.swift" "$ROOT/JarvisEVO/Core/VisionModelPair.swift" \
 "$ROOT/JarvisEVO/Services/Vision/VisionWorker.swift" "$ROOT/JarvisEVO/Services/Vision/NativeVisionRuntime.swift" \
 "$ROOT/Diagnostics/VisionProof/Linux/production_runtime_check.swift" -Xlinker "$LIB" -o "$OUT/runtime-check"
"$OUT/runtime-check" "$MODELS"
