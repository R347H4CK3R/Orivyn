#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
ARTIFACTS="artifacts/$RUN_ID"
PACKAGE="build/package-$RUN_ID"
mkdir -p "$ARTIFACTS"
export ARTIFACTS
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
node --test scripts/vm-tests/*.test.cjs
node --test scripts/agent-tests/*.test.cjs
python3 -m unittest discover -s scripts/tests -v 2>&1 | tee "$ARTIFACTS/package-tests.log"
if ! command -v xcodebuild >/dev/null; then echo 'Xcode 26+ is required; native tests have not run.' >&2; exit 2; fi
xcodebuild -version | tee "$ARTIFACTS/xcode-version.txt"
xcodebuild -showsdks | tee "$ARTIFACTS/sdks.txt"
xcodebuild -showsdks | grep -Eq 'iphoneos2[6-9]' || { echo 'iOS 26+ SDK is required.' >&2; exit 2; }
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$ARTIFACTS/test-model-path.txt"
xcodegen generate
xcrun simctl list devices available -j > "$ARTIFACTS/simulators.json"
SIMULATOR_ID=$(python3 - <<'PY'
import json,os
items=json.load(open(os.path.join(os.environ['ARTIFACTS'],'simulators.json')))['devices']
choices=[d for runtime, values in items.items() if 'iOS-26' in runtime for d in values if 'iPhone' in d['name'] and d.get('isAvailable')]
if not choices: raise SystemExit('No iOS 26 iPhone simulator is installed')
choices.sort(key=lambda d: (d['name'] != 'iPhone 16 Plus', d['name']))
print(choices[0]['udid'])
PY
)
echo "$SIMULATOR_ID" > "$ARTIFACTS/simulator-id.txt"
python3 scripts/boot_ci_simulator.py --simulator "$SIMULATOR_ID" --evidence "$ARTIFACTS/simulator-boot.json"
# Deterministic real Core Location simulator input, not physical GPS evidence.
xcrun simctl location "$SIMULATOR_ID" set 37.3349,-122.0090
bash scripts/run_native_tests.sh "$ARTIFACTS" xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 720 -resultBundlePath "$ARTIFACTS/Tests.xcresult" CODE_SIGNING_ALLOWED=NO "ORIVYN_NATIVE_FEATURES=${ORIVYN_NATIVE_FEATURES:-}" JARVIS_REQUIRE_REAL_INFERENCE=1 test
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "ORIVYN_NATIVE_FEATURES=${ORIVYN_NATIVE_FEATURES:-}" build 2>&1 | tee "$ARTIFACTS/device-build.log"
APP=build/Build/Products/Release-iphoneos/JarvisEVO.app
test -x "$APP/JarvisEVO"
mkdir -p "$PACKAGE/Payload"
cp -R "$APP" "$PACKAGE/Payload/"
IPA_NAME=$(python3 scripts/ipa_filename.py "$APP/Info.plist")
IPA_PATH="$PWD/$ARTIFACTS/$IPA_NAME"
(cd "$PACKAGE" && zip -qr "$IPA_PATH" Payload)
python3 scripts/verify_ipa.py "$IPA_PATH" --output "$ARTIFACTS/ipa-verification.json"
(cd "$ARTIFACTS" && shasum -a 256 "$IPA_NAME" > SHA256SUMS)
echo 'Build and package checks completed. Model/device/fidelity acceptance gates remain independent.'
