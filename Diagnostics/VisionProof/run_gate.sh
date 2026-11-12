#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
EVIDENCE="$2"
cd "$ROOT"

  set -euo pipefail
  export VISION_MODEL_DIR="$ROOT/.cache/test-models/vision"
  python3 Diagnostics/VisionProof/download_pair.py "$VISION_MODEL_DIR"
  xcrun simctl list devices available -j > "$EVIDENCE/simulators.json"
  SIMULATOR_ID=$(python3 -c 'import json; v=json.load(open("artifacts/native-capabilities/simulators.json"))["devices"]; ds=[d for r,items in v.items() if "iOS-26" in r for d in items if "iPhone" in d["name"] and d.get("isAvailable")]; ds.sort(key=lambda d:(d["name"]!="iPhone 16 Plus",d["name"])); print(ds[0]["udid"])')
  xcrun simctl bootstatus "$SIMULATOR_ID" -b
  export VISION_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
  bash Diagnostics/VisionProof/run_native.sh
