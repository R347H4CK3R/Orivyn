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
python3 scripts/generate_project.py
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
# Standard complete app unit target, same selector as the main core gate.
mkdir -p "$EVIDENCE/core"
plutil -convert json -o "$EVIDENCE/shipping-project.json" JarvisEVO.xcodeproj/project.pbxproj
python3 scripts/verify_project_graph.py "$EVIDENCE/shipping-project.json"
set +e
bash scripts/run_native_tests.sh "$EVIDENCE/core" xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -destination "$VISION_DESTINATION" -destination-timeout 120 -derivedDataPath "$VISION_DERIVED_DATA" \
 -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
 -maximum-test-execution-time-allowance 720 -only-testing:JarvisEVOTests \
 -resultBundlePath "$EVIDENCE/core/Tests.xcresult" CODE_SIGNING_ALLOWED=NO \
 "ORIVYN_NATIVE_FEATURES=$ORIVYN_NATIVE_FEATURES" JARVIS_REQUIRE_REAL_INFERENCE=1 test
CORE_STATUS=$?
set -e


export ORIVYN_VISION_MODEL_DIR="$RUNNER_TEMP/orivyn-vision-pair"

git rev-parse HEAD > "$EVIDENCE/source-commit.txt"
xcodebuild -version > "$EVIDENCE/xcode-version.txt"
# Sequential model lifetimes keep these large fixtures out of the app bundle and
# prevent production models from occupying memory at once. Preserve all
# outcomes even if one gate fails; neither can be reported green on a skip.
set +e
(python3 Diagnostics/VisionProof/prepare_production_pair.py "$ORIVYN_VISION_MODEL_DIR" && bash Diagnostics/VisionProof/run_production_simulator.sh) > "$EVIDENCE/vision-gate.log" 2>&1
VISION_STATUS=$?
run_native_gate() {
 local id="$1" fixture="$2" kind="$3" evidence="$4"
 local filename
 case "$id" in
  qwen3-1.7b-q8_0) filename='Qwen3-1.7B-Q8_0.gguf' ;;
  qwen3-1.7b-q4_k_m) filename='Qwen3-1.7B-Q4_K_M.gguf' ;;
  *) return 2 ;;
 esac
 export ORIVYN_PRODUCTION_MODEL_ID="$id" ORIVYN_NATIVE_TOOLS_MODEL_DIR="$fixture"
 export NATIVE_TOOLS_GATE_KIND="$kind" NATIVE_TOOLS_EVIDENCE_DIR="$evidence"
 python3 Diagnostics/NativeTools/download.py --model-id "$id" --output "$fixture/$filename" && bash Diagnostics/NativeTools/run_production_simulator.sh
}
export ORIVYN_REQUIRE_NATIVE_TRANSCRIPT_ROUTE=1
run_native_gate qwen3-1.7b-q4_k_m "$RUNNER_TEMP/orivyn-native-q4" reviewed-plan "$EVIDENCE/reviewed-plan-q4" > "$EVIDENCE/reviewed-plan-q4-gate.log" 2>&1
REVIEWED_STATUS=$?
set -e
printf 'core=%s\nvision=%s\nreviewed_native_route=%s\n' "$CORE_STATUS" "$VISION_STATUS" "$REVIEWED_STATUS" | tee "$EVIDENCE/outcomes.txt"
tail -n 100 "$EVIDENCE/vision-gate.log"
tail -n 100 "$EVIDENCE/reviewed-plan-q4-gate.log"
[[ "$CORE_STATUS" == 0 && "$VISION_STATUS" == 0 && "$REVIEWED_STATUS" == 0 ]]
