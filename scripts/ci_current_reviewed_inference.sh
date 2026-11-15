#!/bin/bash
# Narrow real-model regression on current preview source, never a release gate.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
: "${RUNNER_TEMP:?Hosted temporary directory required}"
: "${ORIVYN_COMBINED_RUNTIME_ARCHIVE:?Verified runtime required}"
: "${ORIVYN_NATIVE_FEATURES:?Native features required}"
OUT="$ROOT/artifacts/current-reviewed-inference"
mkdir -p "$OUT"
printf '%s\n' 'Real simulator reviewed-plan proposal/approval/search/read/answer only. Not generic autonomy, physical-device acceptance, live sync, or 1.0 completion.' > "$OUT/SCOPE.txt"
git rev-parse HEAD > "$OUT/source-commit.txt"
xcodebuild -version > "$OUT/xcode-version.txt"
shasum -a 256 Tests/ProductionReviewedReadPlanTests.swift JarvisEVO/Core/NativeModelSnapshot.swift JarvisEVO/Providers/Local/ModelInstallTransaction.swift > "$OUT/source-hashes.txt"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$OUT/shared-test-model-path.txt"
python3 scripts/generate_project.py
xcrun simctl list devices available -j > "$OUT/simulators.json"
SIMULATOR_ID=$(python3 scripts/select_reviewed_runtime.py "$OUT/simulators.json")
python3 scripts/boot_ci_simulator.py --simulator "$SIMULATOR_ID" --timeout 300 --evidence "$OUT/boot.json"
export NATIVE_TOOLS_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
export NATIVE_TOOLS_DERIVED_DATA="$RUNNER_TEMP/orivyn-current-reviewed-derived"
export NATIVE_TOOLS_EVIDENCE_DIR="$OUT/reviewed-plan"
export ORIVYN_PRODUCTION_MODEL_ID=qwen3-1.7b-q4_k_m
export ORIVYN_NATIVE_TOOLS_MODEL_DIR="$RUNNER_TEMP/orivyn-current-reviewed-q4"
export NATIVE_TOOLS_GATE_KIND=reviewed-plan
export ORIVYN_REQUIRE_NATIVE_TRANSCRIPT_ROUTE=1
python3 Diagnostics/NativeTools/download.py --model-id "$ORIVYN_PRODUCTION_MODEL_ID" --output "$ORIVYN_NATIVE_TOOLS_MODEL_DIR/Qwen3-1.7B-Q4_K_M.gguf" > "$OUT/model-path.txt"
bash Diagnostics/NativeTools/run_production_simulator.sh
