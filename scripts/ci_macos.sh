#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
ARTIFACTS="artifacts/$RUN_ID"
PACKAGE="build/package-$RUN_ID"
mkdir -p "$ARTIFACTS"
export ARTIFACTS
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
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 240 -resultBundlePath "$ARTIFACTS/Tests.xcresult" CODE_SIGNING_ALLOWED=NO JARVIS_REQUIRE_REAL_INFERENCE=1 test 2>&1 | tee "$ARTIFACTS/native-tests.log"
xcrun xcresulttool export attachments --path "$ARTIFACTS/Tests.xcresult" --output-path "$ARTIFACTS/screenshots" || true
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | tee "$ARTIFACTS/device-build.log"
APP=build/Build/Products/Release-iphoneos/JarvisEVO.app
test -x "$APP/JarvisEVO"
mkdir -p "$PACKAGE/Payload"
cp -R "$APP" "$PACKAGE/Payload/"
IPA_PATH="$PWD/$ARTIFACTS/Jarvis-EVO-0.1.0-unsigned.ipa"
(cd "$PACKAGE" && zip -qr "$IPA_PATH" Payload)
python3 scripts/verify_ipa.py "$IPA_PATH" --output "$ARTIFACTS/ipa-verification.json"
(cd "$ARTIFACTS" && shasum -a 256 Jarvis-EVO-0.1.0-unsigned.ipa > SHA256SUMS)
echo 'Build and package checks completed. Model/device/fidelity acceptance gates remain independent.'
