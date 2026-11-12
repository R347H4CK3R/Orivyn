#!/usr/bin/env bash
# Parent invokes within its separately bounded combined gate. No framework build,
# model download, simulator choice/boot, CI launch, signing or packaging here.
set -euo pipefail
cd "$(dirname "$0")"
: "${VISION_MODEL_DIR:?Provide existing immutable verified research pair directory}"
: "${VISION_DESTINATION:?Provide existing simulator destination, e.g. platform=iOS Simulator,id=...}"
[[ -d Frameworks/llama.xcframework ]] || { echo 'Missing newly built combined mtmd framework'; exit 1; }
python3 -m unittest discover -s tests -v
python3 verify_pair.py "$VISION_MODEL_DIR"
export VISION_REQUIRE_REAL=1
xcodegen generate
mkdir -p artifacts
# Existing result paths intentionally fail rather than erase prior evidence.
xcodebuild test -project VisionProof.xcodeproj -scheme VisionProof \
 -destination "$VISION_DESTINATION" -parallel-testing-enabled NO \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
 -maximum-test-execution-time-allowance 180 \
 -resultBundlePath artifacts/VisionProof.xcresult CODE_SIGNING_ALLOWED=NO VISION_MODEL_DIR="$VISION_MODEL_DIR" VISION_REQUIRE_REAL=1
