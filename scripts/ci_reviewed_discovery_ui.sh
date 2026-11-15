#!/bin/bash
# One exact UI regression; test-storage only, no model inference or publication.
set -euo pipefail
cd "$(dirname "$0")/.."
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
: "${RUNNER_TEMP:?Hosted temporary directory required}"
: "${ORIVYN_COMBINED_RUNTIME_ARCHIVE:?Verified native runtime required}"
OUT="$PWD/artifacts/reviewed-discovery-ui"
mkdir -p "$OUT"
git rev-parse HEAD > "$OUT/source-commit.txt"
xcodebuild -version > "$OUT/xcode-version.txt"
printf '%s\n' 'Simulator UI discovery, explicit experimental disclosure and saved-task no-autoexecution only. Not model inference, physical-device acceptance or generic-autonomy repair.' > "$OUT/SCOPE.txt"
shasum -a 256 JarvisEVO/UI/LocalAgentView.swift UITests/LocalAgentIntegrationUITests.swift > "$OUT/source-hashes.txt"
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
 -derivedDataPath "$RUNNER_TEMP/orivyn-discovery-ui-derived" \
 -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
 -parallel-testing-enabled NO -test-timeouts-enabled YES \
 -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 300 \
 -only-testing:JarvisEVOUITests/LocalAgentIntegrationUITests/testSavedTaskSurvivesRelaunchWithoutAutomaticExecution \
 -resultBundlePath "$OUT/Tests.xcresult" CODE_SIGNING_ALLOWED=NO test > "$OUT/xcodebuild.log" 2>&1
status=$?
set -e
printf '%s\n' "$status" > "$OUT/exit.txt"
xcrun xcresulttool get test-results summary --path "$OUT/Tests.xcresult" > "$OUT/test-summary.json"
xcrun xcresulttool export attachments --path "$OUT/Tests.xcresult" --output-path "$OUT/attachments"
python3 Diagnostics/NativeTools/verify_simulator_result.py "$OUT/test-summary.json"
test "$status" -eq 0
