#!/bin/bash
# Public, synthetic-only native acceptance gate. Never publishes an IPA/release.
set -euo pipefail
cd "$(dirname "$0")/.."
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
: "${RUNNER_TEMP:?}"
A="$PWD/artifacts/archive-restore"; mkdir -p "$A"
git rev-parse HEAD > "$A/source-commit.txt"
printf '%s\n' 'Actual synthetic ZIP selection through the iOS Files provider, review, transactional commit and relaunch history; retained preparation recovery; native core tests. No physical-device or user-archive verification. No release publication.' > "$A/SCOPE.txt"
# Separate macOS package gate; its count is not part of the 51 simulator tests.
swift test --jobs 2 --package-path Packages/ArchiveExtraction > "$A/extractor-package.log" 2>&1
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$A/test-model-path.txt"
python3 scripts/generate_project.py
xcrun simctl list devices available -j > "$A/simulators.json"
SIM=$(python3 scripts/select_reviewed_runtime.py "$A/simulators.json")
python3 scripts/boot_ci_simulator.py --simulator "$SIM" --timeout 300 --evidence "$A/boot.json"
ARCHIVE_RESTORE_SIMULATOR="$SIM" bash Diagnostics/ArchiveRestore/prepare_fixture.sh > "$A/provider-fixture.log" 2>&1
set +e
xcodebuild test -project JarvisEVO.xcodeproj -scheme JarvisEVO -derivedDataPath "$RUNNER_TEMP/orivyn-archive-restore-derived" \
 -destination "platform=iOS Simulator,id=$SIM" -destination-timeout 120 -parallel-testing-enabled NO \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 300 \
 -only-testing:JarvisEVOTests/ChatGPTConversationRestoreTests \
 -only-testing:JarvisEVOTests/ChatGPTRecordStreamTests \
 -only-testing:JarvisEVOTests/ArchivePreservationTests \
 -only-testing:JarvisEVOTests/ArchiveAttachmentAssociationTests \
 -only-testing:JarvisEVOTests/ArchiveRestorePersistenceTests \
 -only-testing:JarvisEVOUITests/ArchiveRestoreUITests \
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
expected={'totalTestCount':51,'passedTests':51,'failedTests':0,'skippedTests':0}
for k,v in expected.items():
 assert type(s.get(k)) is int and s[k]==v,(k,s.get(k),v)
print('51 required native/simulator tests passed without skips. Physical device and private archive remain unverified.')
PY
