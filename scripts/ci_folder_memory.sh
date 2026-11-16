#!/bin/bash
# Isolated development validation. No publishing, no physical-device claim.
set -euo pipefail
cd "$(dirname "$0")/.."
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
: "${RUNNER_TEMP:?}"
A="$PWD/artifacts/folder-memory"; mkdir -p "$A"
git rev-parse HEAD > "$A/source-commit.txt"
echo 'iOS simulator native components plus actual Files picker cancel/reopen. Does not verify selecting the user archive or physical device/provider behavior.' > "$A/SCOPE.txt"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$A/test-model-path.txt"
python3 scripts/generate_project.py
xcrun simctl list devices available -j > "$A/simulators.json"
SIM=$(python3 scripts/select_reviewed_runtime.py "$A/simulators.json")
python3 scripts/boot_ci_simulator.py --simulator "$SIM" --timeout 300 --evidence "$A/boot.json"
set +e
xcodebuild test -project JarvisEVO.xcodeproj -scheme JarvisEVO -derivedDataPath "$RUNNER_TEMP/orivyn-folder-memory-derived" \
 -destination "platform=iOS Simulator,id=$SIM" -destination-timeout 120 -parallel-testing-enabled NO \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 300 \
 -only-testing:JarvisEVOTests/FolderMemoryImportTests \
 -only-testing:JarvisEVOTests/FolderMemoryPersistenceTests \
 -only-testing:JarvisEVOTests/MemorySearchTests \
 -only-testing:JarvisEVOTests/FolderMemoryNativeIntegrationTests \
 -only-testing:JarvisEVOUITests/FolderMemoryImportUITests \
 -resultBundlePath "$A/Tests.xcresult" CODE_SIGNING_ALLOWED=NO > "$A/xcodebuild.log" 2>&1
status=$?
set -e
if test -d "$A/Tests.xcresult"; then
 xcrun xcresulttool get test-results summary --path "$A/Tests.xcresult" > "$A/summary.json"
 xcrun xcresulttool export attachments --path "$A/Tests.xcresult" --output-path "$A/attachments"
fi
test "$status" = 0
python3 - "$A/summary.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
expected={'totalTestCount':21,'passedTests':21,'failedTests':0,'skippedTests':0}
for k,v in expected.items():
 assert type(s.get(k)) is int and s[k]==v,(k,s.get(k),v)
print('21 required native/simulator tests passed without skips; no physical-device acceptance claim.')
PY
