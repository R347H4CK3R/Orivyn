#!/bin/bash
# Required real-model simulator gates; independent from the aggregate UI suite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${RUNNER_TEMP:?Dedicated GitHub runner required}"
: "${ORIVYN_COMBINED_RUNTIME_ARCHIVE:?Verified combined runtime required}"
: "${ORIVYN_NATIVE_FEATURES:?Both native features required}"
EVIDENCE="$ROOT/artifacts/production-inference"
mkdir -p "$EVIDENCE"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
# The shared test target has this resource even with an only-testing selector.
python3 scripts/download_test_model.py > "$EVIDENCE/chat-test-model-path.txt"
xcodegen generate
xcrun simctl list devices available -j > "$EVIDENCE/simulators.json"
SIMULATOR_ID=$(python3 - "$EVIDENCE/simulators.json" <<'PY'
import json,sys
items=json.load(open(sys.argv[1]))['devices']
choices=[d for runtime, values in items.items() if 'iOS-26' in runtime for d in values if 'iPhone' in d['name'] and d.get('isAvailable')]
if not choices: raise SystemExit('No iOS 26 iPhone simulator is installed')
choices.sort(key=lambda d:(d['name']!='iPhone 16 Plus',d['name']))
print(choices[0]['udid'])
PY
)
python3 scripts/boot_ci_simulator.py --simulator "$SIMULATOR_ID" --evidence "$EVIDENCE/simulator-boot.json"
export VISION_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
export NATIVE_TOOLS_DESTINATION="$VISION_DESTINATION"
export VISION_DERIVED_DATA="$RUNNER_TEMP/orivyn-inference-derived"
export NATIVE_TOOLS_DERIVED_DATA="$VISION_DERIVED_DATA"
export VISION_EVIDENCE_DIR="$EVIDENCE/vision"
export NATIVE_TOOLS_EVIDENCE_DIR="$EVIDENCE/native-tools"
export ORIVYN_VISION_MODEL_DIR="$RUNNER_TEMP/orivyn-vision-pair"
export ORIVYN_NATIVE_TOOLS_MODEL_DIR="$RUNNER_TEMP/orivyn-native-tools-model"
git rev-parse HEAD > "$EVIDENCE/source-commit.txt"
xcodebuild -version > "$EVIDENCE/xcode-version.txt"
# Sequential model lifetimes keep these large fixtures out of the app bundle and
# prevent both production models from occupying memory at once. Preserve both
# outcomes even if one gate fails; neither can be reported green on a skip.
set +e
(python3 Diagnostics/VisionProof/prepare_production_pair.py "$ORIVYN_VISION_MODEL_DIR" && bash Diagnostics/VisionProof/run_production_simulator.sh) > "$EVIDENCE/vision-gate.log" 2>&1
VISION_STATUS=$?
(python3 Diagnostics/NativeTools/download.py --output "$ORIVYN_NATIVE_TOOLS_MODEL_DIR/Qwen3-1.7B-Q8_0.gguf" && bash Diagnostics/NativeTools/run_production_simulator.sh) > "$EVIDENCE/native-tools-gate.log" 2>&1
TOOLS_STATUS=$?
set -e
printf 'vision=%s\nnative_tools=%s\n' "$VISION_STATUS" "$TOOLS_STATUS" | tee "$EVIDENCE/outcomes.txt"
tail -n 100 "$EVIDENCE/vision-gate.log"
tail -n 100 "$EVIDENCE/native-tools-gate.log"
[[ "$VISION_STATUS" == 0 && "$TOOLS_STATUS" == 0 ]]
