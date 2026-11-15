#!/bin/bash
# No simctl/boot: host-native component execution plus iOS compile-only proof.
set -euo pipefail
cd "$(dirname "$0")/.."
A=artifacts/backup-without-boot
mkdir -p "$A"
git rev-parse HEAD > "$A/source-commit.txt"
xcodebuild -version > "$A/xcode-version.txt"
printf '%s\n' 'macOS component tests plus iOS compile-only. No iOS test execution, Files-provider grants, or release acceptance.' > "$A/SCOPE.txt"
python3 scripts/prepare_backup_host_tests.py --output "$A/host"
swift test --package-path "$A/host" --jobs 2 2>&1 | tee "$A/host-tests.log"
python3 - "$A/host-tests.log" <<'PY'
import re,sys
text=open(sys.argv[1]).read()
assert not re.search(r'Test Case .* skipped|\b[1-9][0-9]* (?:tests? )?skipped',text), 'Skipped checks are not allowed'
assert re.search(r'Executed 156 tests, with 0 failures',text), 'Expected all 156 Darwin XCTest component checks, no zero-test pass'
PY
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$A/test-model-path.txt"
python3 scripts/generate_project.py
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -destination 'generic/platform=iOS Simulator' \
 -derivedDataPath "$A/DerivedData" CODE_SIGNING_ALLOWED=NO build-for-testing \
 2>&1 | tee "$A/compile-only.log"
test -n "$(find "$A/DerivedData/Build/Products" -name '*.xctestrun' -print -quit)"
printf '%s\n' 'Compile-only succeeded. iOS tests NOT executed.' > "$A/compile-result.txt"
