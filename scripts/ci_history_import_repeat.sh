#!/bin/bash
# Three independent observations; no retry-until-pass and no release packaging.
set -euo pipefail
cd "$(dirname "$0")/.."
export ARTIFACTS=artifacts/history-import-repeat
mkdir -p "$ARTIFACTS"
git rev-parse HEAD > "$ARTIFACTS/source-commit.txt"
printf '%s\n' 'Three independent history import cancellation observations. No retries or full acceptance.' > "$ARTIFACTS/SCOPE.txt"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
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

overall=0
for attempt in 1 2 3; do
  evidence="$ARTIFACTS/attempt-$attempt"
  mkdir -p "$evidence"
  set +e
  bash scripts/run_native_tests.sh "$evidence" xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 720 -only-testing:JarvisEVOUITests/JarvisEVOUITests/testHistoryImportCancellationReturnsToSettingsAndPreservesComposer -resultBundlePath "$evidence/Tests.xcresult" CODE_SIGNING_ALLOWED=NO "ORIVYN_NATIVE_FEATURES=${ORIVYN_NATIVE_FEATURES:-}" JARVIS_REQUIRE_REAL_INFERENCE=1 test
  status=$?
  xcrun simctl spawn "$SIMULATOR_ID" log show --style json --last 1h --predicate 'subsystem == "app.jarvisevo.boundary-diagnostic"' > "$evidence/boundary-lifecycle.json" 2> "$evidence/navigation-log-export.txt"
  export_status=$?
  set -e
  printf '%s\n' "$status" > "$evidence/test-exit.txt"
  printf '%s\n' "$export_status" > "$evidence/log-export-exit.txt"
  if (( status != 0 || export_status != 0 )); then overall=1; fi
  if [[ -d "$evidence/Tests.xcresult" ]]; then
    xcrun xcresulttool get test-results summary --path "$evidence/Tests.xcresult" > "$evidence/test-summary.json"
    python3 - "$evidence/test-summary.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s.get("totalTestCount")==1 and s.get("skippedTests",0)==0 and s.get("failedTests",0)==0 and s.get("passedTests")==1, "Expected one executed, unskipped test"
PY
  else
    overall=1
  fi
done
exit "$overall"
