#!/usr/bin/env bash
# Isolated proof projects only. No product IPA, publishing or billing changes.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export HOMEBREW_NO_AUTO_UPDATE=1
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
if ! command -v cmake >/dev/null; then brew install cmake; fi
mkdir -p artifacts/native-capabilities
EVIDENCE="$ROOT/artifacts/native-capabilities"
# Each independent gate keeps its exit status. A BIOS failure does not pretend
# that the separate vision compiler/runtime was tested, nor suppress its result.
set +e
bash Diagnostics/VMProof/run_native.sh 2>&1 | tee "$EVIDENCE/bios.log"
BIOS_STATUS=${PIPESTATUS[0]}
set -e
if [[ -d Diagnostics/VMProof/artifacts ]]; then cp -R Diagnostics/VMProof/artifacts "$EVIDENCE/bios"; fi
SOURCE="$ROOT/.cache/vision-runtime/llama-b9049"

set +e
bash Diagnostics/VisionRuntime/run_build.sh "$ROOT" "$EVIDENCE" 2>&1 | tee "$EVIDENCE/framework.log"
FRAMEWORK_STATUS=${PIPESTATUS[0]}
set -e
VISION_STATUS=125
if (( FRAMEWORK_STATUS == 0 )); then

 set +e
 bash Diagnostics/VisionProof/run_gate.sh "$ROOT" "$EVIDENCE" 2>&1 | tee "$EVIDENCE/vision.log"
 VISION_STATUS=${PIPESTATUS[0]}
 set -e
 if [[ -d Diagnostics/VisionProof/artifacts ]]; then
  cp -R Diagnostics/VisionProof/artifacts "$EVIDENCE/vision"
  if [[ -d "$EVIDENCE/vision/VisionProof.xcresult" ]]; then
   xcrun xcresulttool export attachments --path "$EVIDENCE/vision/VisionProof.xcresult" --output-path "$EVIDENCE/vision/screenshots" || true
  fi
 fi
fi
printf 'BIOS_STATUS=%s\nFRAMEWORK_STATUS=%s\nVISION_STATUS=%s\n' "$BIOS_STATUS" "$FRAMEWORK_STATUS" "$VISION_STATUS" | tee "$EVIDENCE/status.txt"
# Bundle modest logs/images separately from the potentially large result bundles.
bash scripts/run_native_tests.sh --bundle-evidence artifacts || true
(( BIOS_STATUS == 0 && FRAMEWORK_STATUS == 0 && VISION_STATUS == 0 ))
