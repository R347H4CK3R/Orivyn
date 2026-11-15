#!/bin/bash
# Isolated simulator review/relaunch UI, then separate real-model acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
: "${RUNNER_TEMP:?}"
: "${ORIVYN_COMBINED_RUNTIME_ARCHIVE:?}"
OUT="$PWD/artifacts/completion-acceptance";mkdir -p "$OUT"
git rev-parse HEAD > "$OUT/source-commit.txt"
printf '%s\n' 'Two UI no-auto-run checks plus separate real Qwen completion contract. No physical-device/general-autonomy claims.' > "$OUT/SCOPE.txt"
shasum -a 256 UITests/LocalCompletionUITests.swift Tests/ProductionCompletionContractTests.swift scripts/seed_completion_ui.py JarvisEVO/UI/LocalAgentView.swift JarvisEVO/Services/LocalAgentSession.swift > "$OUT/source-hashes.txt"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$OUT/shared-test-model-path.txt"
python3 scripts/generate_project.py
xcrun simctl list devices available -j > "$OUT/simulators.json"
SIM=$(python3 scripts/select_reviewed_runtime.py "$OUT/simulators.json")
python3 scripts/boot_ci_simulator.py --simulator "$SIM" --timeout 300 --evidence "$OUT/boot.json"
DERIVED="$RUNNER_TEMP/orivyn-completion-acceptance-derived"
MODEL_DIR="$RUNNER_TEMP/orivyn-completion-acceptance-model"
MODEL="$MODEL_DIR/Qwen3-1.7B-Q4_K_M.gguf"
python3 Diagnostics/NativeTools/download.py --model-id qwen3-1.7b-q4_k_m --output "$MODEL" > "$OUT/model-path.txt"
run_ui() {
xcodebuild build-for-testing -project JarvisEVO.xcodeproj -scheme JarvisEVO -derivedDataPath "$DERIVED" -destination "platform=iOS Simulator,id=$SIM" CODE_SIGNING_ALLOWED=NO > "$OUT/build.log" 2>&1
xcrun simctl install "$SIM" "$DERIVED/Build/Products/Debug-iphonesimulator/JarvisEVO.app"
xcrun simctl launch "$SIM" app.jarvisevo.ios --uitesting --reset-test-storage
CONTAINER=$(xcrun simctl get_app_container "$SIM" app.jarvisevo.ios data)
# Bound initial startup; only fresh simulator test state is reset above.
for i in $(seq 1 60); do test ! -f "$CONTAINER/Library/Application Support/JarvisEVOUITests/conversations.sqlite" || break; sleep 1; done
test -f "$CONTAINER/Library/Application Support/JarvisEVOUITests/conversations.sqlite"
xcrun simctl terminate "$SIM" app.jarvisevo.ios
python3 scripts/seed_completion_ui.py --simulator "$SIM" --model "$MODEL" > "$OUT/seed-path.txt"
for PHASE in approval relaunch; do
 if test "$PHASE" = approval; then METHOD=testReviewDiscardApprovalAndRelaunchRequireExplicitRun; else METHOD=testRelaunchPreservesApprovedScopeWithoutExecution; fi
 mkdir "$OUT/$PHASE"
 set +e
 xcodebuild test-without-building -project JarvisEVO.xcodeproj -scheme JarvisEVO -derivedDataPath "$DERIVED" -destination "platform=iOS Simulator,id=$SIM" -destination-timeout 120 -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600 "-only-testing:JarvisEVOUITests/LocalCompletionUITests/$METHOD" -resultBundlePath "$OUT/$PHASE/Tests.xcresult" CODE_SIGNING_ALLOWED=NO > "$OUT/$PHASE/xcodebuild.log" 2>&1
 status=$?
 set -e
 xcrun xcresulttool get test-results summary --path "$OUT/$PHASE/Tests.xcresult" > "$OUT/$PHASE/summary.json"
 xcrun xcresulttool export attachments --path "$OUT/$PHASE/Tests.xcresult" --output-path "$OUT/$PHASE/attachments"
 python3 Diagnostics/NativeTools/verify_simulator_result.py "$OUT/$PHASE/summary.json"
 test "$status" = 0
 # Re-query exact installed app container because test runner may reinstall app.
 CONTAINER=$(xcrun simctl get_app_container "$SIM" app.jarvisevo.ios data)
 mkdir "$OUT/$PHASE/tasks"
 cp "$CONTAINER/Library/Application Support/JarvisEVOUITests/LocalAgentTasks/"*.json "$OUT/$PHASE/tasks/"
done
python3 scripts/verify_completion_ui_state.py "$OUT/approval/tasks" "$OUT/relaunch/tasks" > "$OUT/verified-task.json"
}

run_real_model() {
export NATIVE_TOOLS_DESTINATION="platform=iOS Simulator,id=$SIM"
export NATIVE_TOOLS_DERIVED_DATA="$DERIVED"
export NATIVE_TOOLS_EVIDENCE_DIR="$OUT/real-model"
export ORIVYN_PRODUCTION_MODEL_ID=qwen3-1.7b-q4_k_m
export ORIVYN_NATIVE_TOOLS_MODEL_DIR="$MODEL_DIR"
export NATIVE_TOOLS_GATE_KIND=completion
bash Diagnostics/NativeTools/run_production_simulator.sh
}

source scripts/completion_acceptance_phases.sh
