#!/bin/bash
# Exact contract and deterministic-output session tests, synthetic stores only.
set -euo pipefail
cd "$(dirname "$0")/.."
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
: "${RUNNER_TEMP:?Hosted temporary directory required}"
: "${ORIVYN_COMBINED_RUNTIME_ARCHIVE:?Verified native runtime required}"
OUT="$PWD/artifacts/completion-session"
mkdir -p "$OUT"
git rev-parse HEAD > "$OUT/source-commit.txt"
xcodebuild -version > "$OUT/xcode-version.txt"
printf '%s\n' 'Native contract and session enforcement using deterministic model output and real local dispatch. Not real inference, UI acceptance, physical-device acceptance or general autonomy.' > "$OUT/SCOPE.txt"
shasum -a 256 JarvisEVO/Core/LocalCompletion*.swift JarvisEVO/Services/LocalAgentSession.swift JarvisEVO/Core/LocalAgentSnapshot.swift JarvisEVO/Resources/LocalAgentCore.js Tests/LocalCompletion*.swift Tests/LocalAgentVersionRoutingTests.swift > "$OUT/source-hashes.txt"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$OUT/shared-test-model-path.txt"
python3 scripts/generate_project.py
xcrun simctl list devices available -j > "$OUT/simulators.json"
SIMULATOR_ID=$(python3 scripts/select_reviewed_runtime.py "$OUT/simulators.json")
python3 scripts/boot_ci_simulator.py --simulator "$SIMULATOR_ID" --timeout 300 --evidence "$OUT/boot.json"
set +e
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -derivedDataPath "$RUNNER_TEMP/orivyn-completion-session-derived" \
 -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
 -parallel-testing-enabled NO -test-timeouts-enabled YES \
 -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 300 \
 -only-testing:JarvisEVOTests/LocalCompletionContractTests \
 -only-testing:JarvisEVOTests/LocalAgentVersionRoutingTests \
 -only-testing:JarvisEVOTests/LocalCompletionGrammarTests \
 -only-testing:JarvisEVOTests/LocalCompletionReviewTests \
 -only-testing:JarvisEVOTests/LocalCompletionSessionTests \
 -resultBundlePath "$OUT/Tests.xcresult" CODE_SIGNING_ALLOWED=NO test > "$OUT/xcodebuild.log" 2>&1
status=$?
set -e
printf '%s\n' "$status" > "$OUT/exit.txt"
xcrun xcresulttool get test-results summary --path "$OUT/Tests.xcresult" > "$OUT/test-summary.json"
xcrun xcresulttool export attachments --path "$OUT/Tests.xcresult" --output-path "$OUT/attachments"
python3 scripts/verify_completion_gate.py "$OUT/test-summary.json"
test "$status" -eq 0
