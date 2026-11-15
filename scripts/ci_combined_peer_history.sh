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
python3 scripts/generate_project.py --peer
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
python3 scripts/boot_ci_simulator.py --simulator "$SIMULATOR_ID" --evidence "$ARTIFACTS/simulator-boot.json"
# Compile the complete real app and native targets. No inference fixture/model substitution.
# Select thirteen history, four negative session-policy and four real-identity session tests and one actual two-session transport test; evidence validation rejects skips and zero-test success.
# Simulator-only ad-hoc signing supplies the actual host's application/keychain
# entitlements. It is not distribution signing and never uses a developer account.
test_args=(-project JarvisEVO.xcodeproj -scheme JarvisEVO
 -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 60
 -parallel-testing-enabled NO -test-timeouts-enabled YES
 -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 600
 -only-testing:JarvisEVOTests/PeerHistoryAppModelTests
 -only-testing:JarvisEVOTests/PeerSyncSessionPolicyTests
 -only-testing:JarvisEVOTests/PeerSyncSessionPairingTests
 -only-testing:JarvisEVOTests/PeerSyncSessionEndToEndTests
 CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=-
 CODE_SIGN_STYLE=Manual CODE_SIGN_ENTITLEMENTS=Diagnostics/PeerProvisioning/SimulatorTestHost.entitlements
 ORIVYN_NATIVE_FEATURES=ORIVYN_PEER_TLS_SPIKE
 -derivedDataPath "$RUNNER_TEMP/orivyn-peer-app-build")
xcodebuild "${test_args[@]}" build-for-testing 2>&1 | tee "$ARTIFACTS/signed-build.log"
host="$RUNNER_TEMP/orivyn-peer-app-build/Build/Products/Debug-iphonesimulator/JarvisEVO.app"
codesign --verify --strict "$host" 2> "$ARTIFACTS/signature-verification.log"
codesign --display --entitlements - --xml "$host" > "$ARTIFACTS/host-entitlements.plist" 2> "$ARTIFACTS/signature-details.log"
python3 - "$ARTIFACTS/host-entitlements.plist" <<'PY'
import plistlib,sys
entitlements=plistlib.load(open(sys.argv[1],'rb'))
expected='ORIVYNTEST.app.jarvisevo.ios'
assert entitlements.get('application-identifier')==expected,entitlements
assert expected in entitlements.get('keychain-access-groups',[]),entitlements
assert entitlements.get('get-task-allow') is True,entitlements
PY
# Always retain xcresult summary even when setup, teardown or a real test fails.
set +e
xcodebuild "${test_args[@]}" -resultBundlePath "$ARTIFACTS/Tests.xcresult" test-without-building \
 2>&1 | tee "$ARTIFACTS/native-tests.log"
test_status=${PIPESTATUS[0]}
set -e
xcrun xcresulttool get test-results summary --path "$ARTIFACTS/Tests.xcresult" > "$ARTIFACTS/test-summary.json"
python3 - "$ARTIFACTS/test-summary.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s['totalTestCount']==22 and s['passedTests']==22 and s['failedTests']==0 and s['skippedTests']==0,s
PY
test "$test_status" -eq 0
echo 'Focused native regression passed. Full suite, real inference, IPA/device acceptance remain separate.'
