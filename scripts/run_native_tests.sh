#!/bin/bash
# Preserve native-test failure while still exporting screenshots for diagnosis.
set -euo pipefail
ARTIFACTS="$1"
shift
set +e
"$@" 2>&1 | tee "$ARTIFACTS/native-tests.log"
TEST_STATUSES=("${PIPESTATUS[@]}")
set -e
if [[ -d "$ARTIFACTS/Tests.xcresult" ]]; then
  xcrun xcresulttool export attachments --path "$ARTIFACTS/Tests.xcresult" --output-path "$ARTIFACTS/screenshots" || true
fi
if (( TEST_STATUSES[0] != 0 )); then exit "${TEST_STATUSES[0]}"; fi
if (( TEST_STATUSES[1] != 0 )); then exit "${TEST_STATUSES[1]}"; fi
