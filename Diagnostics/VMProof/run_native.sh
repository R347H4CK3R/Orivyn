#!/bin/bash
# Internal test harness only; no IPA, upload, remote service or billing action.
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null
python3 materialize_assets.py
./verify.sh
xcodegen generate
mkdir -p artifacts
xcrun simctl list devices available -j > artifacts/simulators.json
SIMULATOR_ID=$(python3 -c 'import json; v=json.load(open("artifacts/simulators.json"))["devices"]; ds=[d for r,items in v.items() if "iOS-26" in r for d in items if "iPhone" in d["name"] and d.get("isAvailable")]; ds.sort(key=lambda d:(d["name"]!="iPhone 16 Plus",d["name"])); print(ds[0]["udid"])')
xcrun simctl bootstatus "$SIMULATOR_ID" -b
set +e
xcodebuild -project OrivynVMProof.xcodeproj -scheme OrivynVMProof -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 90 -resultBundlePath artifacts/Tests.xcresult CODE_SIGNING_ALLOWED=NO test 2>&1 | tee artifacts/native-tests.log
STATUSES=("${PIPESTATUS[@]}")
set -e
if [[ -d artifacts/Tests.xcresult ]]; then
 xcrun xcresulttool export attachments --path artifacts/Tests.xcresult --output-path artifacts/screenshots || true
fi
if (( STATUSES[0] != 0 )); then exit "${STATUSES[0]}"; fi
exit "${STATUSES[1]}"
