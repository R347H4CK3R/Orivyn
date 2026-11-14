#!/bin/bash
# Focused regression only. Not a full gate, inference check, IPA, or release.
set -euo pipefail
cd "$(dirname "$0")/.."
export ARTIFACTS=artifacts/focused
mkdir -p "$ARTIFACTS"
git rev-parse HEAD | tee "$ARTIFACTS/source-commit.txt"
printf '%s\n' 'Focused regression only; no full acceptance, inference or release.' > "$ARTIFACTS/SCOPE.txt"
xcodebuild -version | tee "$ARTIFACTS/xcode-version.txt"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
bash scripts/bootstrap_llama.sh
# XcodeGen includes this real fixture resource even for focused unit tests.
python3 scripts/download_test_model.py > "$ARTIFACTS/test-model-path.txt"
xcodegen generate
xcrun simctl list devices available -j > "$ARTIFACTS/simulators.json"
SIMULATOR_ID=$(python3 - <<'PY'
import json,os
items=json.load(open(os.path.join(os.environ['ARTIFACTS'],'simulators.json')))['devices']
choices=[d for runtime,values in items.items() if 'iOS-26' in runtime for d in values if 'iPhone' in d['name'] and d.get('isAvailable')]
if not choices:raise SystemExit('No iOS26 iPhone simulator available')
choices.sort(key=lambda d:(d['name']!='iPhone 16 Plus',d['name']))
print(choices[0]['udid'])
PY
)
xcrun simctl bootstatus "$SIMULATOR_ID" -b
# Compile the complete real app and native targets. No inference fixture/model substitution.
# Select exactly 39 tests; evidence validation rejects skips and zero-test success.
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 60 \
 -parallel-testing-enabled NO -test-timeouts-enabled YES \
 -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 600 \
 -only-testing:JarvisEVOTests/LocalHeavyWorkTests \
 -only-testing:JarvisEVOTests/BackupKeepBothTests \
 -only-testing:JarvisEVOTests/ConversationTests \
 -only-testing:JarvisEVOUITests/VirtualDesktopIntegrationUITests/testCheckpointSurvivesAppRelaunchAndFreshGuestRead \
 -resultBundlePath "$ARTIFACTS/Tests.xcresult" CODE_SIGNING_ALLOWED=NO test \
 2>&1 | tee "$ARTIFACTS/native-tests.log"
xcrun xcresulttool get test-results summary --path "$ARTIFACTS/Tests.xcresult" > "$ARTIFACTS/test-summary.json"
python3 scripts/verify_focused_summary.py "$ARTIFACTS/test-summary.json"
echo 'Focused native regression passed. Full suite, real inference, IPA/device acceptance remain separate.'
