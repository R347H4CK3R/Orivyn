#!/bin/bash
# Focused on-device-API simulator regression, never packaging or release.
set -euo pipefail
cd "$(dirname "$0")/.."
export ARTIFACTS=artifacts/backup-selected-file
mkdir -p "$ARTIFACTS"
git rev-parse HEAD > "$ARTIFACTS/source-commit.txt"
xcodebuild -version > "$ARTIFACTS/xcode-version.txt"
printf '%s\n' 'Native selected-file state to AppModel and real SQLite integration using synthetic local files. No real Files selection, external provider grant, device, inference or release acceptance.' > "$ARTIFACTS/SCOPE.txt"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$ARTIFACTS/test-model-path.txt"
python3 scripts/generate_project.py
xcrun simctl list devices available -j > "$ARTIFACTS/simulators.json"
SIMULATOR_ID=$(python3 scripts/select_picker_runtime.py "$ARTIFACTS/simulators.json")
python3 scripts/boot_ci_simulator.py --simulator "$SIMULATOR_ID" --evidence "$ARTIFACTS/simulator-boot.json" --timeout 300
set +e
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
 -parallel-testing-enabled NO -test-timeouts-enabled YES \
 -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 \
 -only-testing:JarvisEVOTests/BackupImportConfirmationTests \
 -only-testing:JarvisEVOTests/BackupFileReaderTests \
 -only-testing:JarvisEVOTests/BackupSelectedFileIntegrationTests \
 -resultBundlePath "$ARTIFACTS/Tests.xcresult" CODE_SIGNING_ALLOWED=NO test \
 2>&1 | tee "$ARTIFACTS/native-tests.log"
status=${PIPESTATUS[0]}
set -e
printf '%s\n' "$status" > "$ARTIFACTS/xcodebuild-exit.txt"
xcrun xcresulttool get test-results summary --path "$ARTIFACTS/Tests.xcresult" > "$ARTIFACTS/test-summary.json"
python3 - "$ARTIFACTS/test-summary.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
expected=16
assert s['totalTestCount']==expected and s['passedTests']==expected and s['failedTests']==0 and s['skippedTests']==0,s
PY
test "$status" -eq 0
