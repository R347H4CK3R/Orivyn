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
run_native_gate qwen3-1.7b-q8_0 "$RUNNER_TEMP/orivyn-native-q8" native-tools "$EVIDENCE/native-tools-q8" > "$EVIDENCE/native-tools-q8-gate.log" 2>&1
Q8_STATUS=$?
run_native_gate qwen3-1.7b-q4_k_m "$RUNNER_TEMP/orivyn-native-q4" native-tools "$EVIDENCE/native-tools-q4" > "$EVIDENCE/native-tools-q4-gate.log" 2>&1
Q4_STATUS=$?
# Borrow the same dedicated Q4 directory only after native inference has joined.
# ProductionLocalAgentSessionTests restores the prior installed-model manifest.
run_native_gate qwen3-1.7b-q4_k_m "$RUNNER_TEMP/orivyn-native-q4" local-agent "$EVIDENCE/local-agent-q4" > "$EVIDENCE/local-agent-q4-gate.log" 2>&1
AGENT_STATUS=$?
# Additive acceptance: actual model proposal, explicit approval, then required reads.
# The generic local-agent gate above remains independently required.
run_native_gate qwen3-1.7b-q4_k_m "$RUNNER_TEMP/orivyn-native-q4" reviewed-plan "$EVIDENCE/reviewed-plan-q4" > "$EVIDENCE/reviewed-plan-q4-gate.log" 2>&1
REVIEWED_STATUS=$?
set -e
printf 'vision=%s\nnative_tools_q8=%s\nnative_tools_q4=%s\nlocal_agent_q4=%s\nreviewed_plan_q4=%s\n' "$VISION_STATUS" "$Q8_STATUS" "$Q4_STATUS" "$AGENT_STATUS" "$REVIEWED_STATUS" | tee "$EVIDENCE/outcomes.txt"
for gate in vision native-tools-q8 native-tools-q4 local-agent-q4 reviewed-plan-q4; do tail -n 100 "$EVIDENCE/$gate-gate.log"; done
[[ "$VISION_STATUS" == 0 && "$Q8_STATUS" == 0 && "$Q4_STATUS" == 0 && "$AGENT_STATUS" == 0 && "$REVIEWED_STATUS" == 0 ]]
