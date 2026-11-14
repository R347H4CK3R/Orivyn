#!/bin/bash
# Build and inspect an unsigned development IPA. This is NOT the full native test gate.
set -euo pipefail
cd "$(dirname "$0")/.."
ARTIFACTS="artifacts/package-only"
mkdir -p "$ARTIFACTS"
git rev-parse HEAD > "$ARTIFACTS/source-commit.txt"
git status --short > "$ARTIFACTS/source-status-before.txt"
test ! -s "$ARTIFACTS/source-status-before.txt" || { echo 'Refusing a dirty source checkout.' >&2; exit 2; }
xcodebuild -version | tee "$ARTIFACTS/xcode-version.txt"
xcodebuild -showsdks > "$ARTIFACTS/sdks.txt"
grep -Eq 'iphoneos2[6-9]' "$ARTIFACTS/sdks.txt" || { echo 'iOS 26+ SDK is required.' >&2; exit 2; }
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
bash scripts/bootstrap_llama.sh
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
xcodegen generate
# Device-only build: no simulator boot, test-model download, or implied native-test pass.
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > "$ARTIFACTS/device-build.log" 2>&1
APP=build/Build/Products/Release-iphoneos/JarvisEVO.app
test -x "$APP/JarvisEVO"
PACKAGE=$(mktemp -d "$PWD/build/package-only.XXXXXX")
mkdir -p "$PACKAGE/Payload"
cp -R "$APP" "$PACKAGE/Payload/"
IPA_NAME=$(python3 scripts/ipa_filename.py "$APP/Info.plist")
IPA_PATH="$PWD/$ARTIFACTS/$IPA_NAME"
(cd "$PACKAGE" && zip -qr "$IPA_PATH" Payload)
python3 scripts/verify_ipa.py "$IPA_PATH" --output "$ARTIFACTS/ipa-verification.json"
(cd "$ARTIFACTS" && shasum -a 256 "$IPA_NAME" > SHA256SUMS)
python3 - <<'PY'
import json,pathlib
out=pathlib.Path('artifacts/package-only')
(out/'SCOPE.json').write_text(json.dumps({'source_commit':(out/'source-commit.txt').read_text().strip(),
 'device_build':'passed','ipa_structure_check':'passed','native_unit_tests':'not_run',
 'simulator_ui_tests':'not_run','physical_device_acceptance':'not_run',
 'release_status':'development_candidate_not_1_0_complete'},indent=2)+'\n')
PY
echo 'Unsigned development IPA built and structurally verified. Native tests and device acceptance NOT run.'
