#!/usr/bin/env bash
# Explicit parent-invoked gate. No downloads, CI dispatch, framework build,
# signing, simulator selection/boot, or tracked project edits.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'This gate requires the authorized Mac runner.' >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${ORIVYN_NATIVE_TOOLS_MODEL_DIR:?Dedicated absolute directory prepared with download.py}"
: "${NATIVE_TOOLS_DESTINATION:?Existing platform=iOS Simulator,id=... destination}"
: "${NATIVE_TOOLS_DERIVED_DATA:?Shared absolute DerivedData path used by the full tests}"
: "${NATIVE_TOOLS_EVIDENCE_DIR:?New absolute evidence directory}"
: "${ORIVYN_NATIVE_FEATURES:?Combined runtime feature flags including ORIVYN_NATIVE_TOOLS}"
[[ " $ORIVYN_NATIVE_FEATURES " == *' ORIVYN_NATIVE_TOOLS '* ]] || { echo 'Native-tools build flag is required.' >&2; exit 2; }
[[ "$ORIVYN_NATIVE_TOOLS_MODEL_DIR" == /* && "$NATIVE_TOOLS_DERIVED_DATA" == /* && "$NATIVE_TOOLS_EVIDENCE_DIR" == /* ]] || { echo 'Paths must be absolute.' >&2; exit 2; }
SCHEME="$ROOT/JarvisEVO.xcodeproj/xcshareddata/xcschemes/JarvisEVO.xcscheme"
[[ -f "$SCHEME" ]] || { echo 'Generate the main project with the combined runtime first.' >&2; exit 2; }
mkdir "$NATIVE_TOOLS_EVIDENCE_DIR"
cp "$SCHEME" "$NATIVE_TOOLS_EVIDENCE_DIR/original.xcscheme"
cleanup() {
  local status=$?
  vm_stat > "$NATIVE_TOOLS_EVIDENCE_DIR/host-vm-after.txt" || true
  cp "$NATIVE_TOOLS_EVIDENCE_DIR/original.xcscheme" "$SCHEME" || status=1
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT
# TestAction environment is explicit; shell variables alone do not establish
# simulator test-host propagation. Restore the generated scheme on every exit.
MODEL_ID="${ORIVYN_PRODUCTION_MODEL_ID:-qwen3-1.7b-q8_0}"
GATE_KIND="${NATIVE_TOOLS_GATE_KIND:-native-tools}"
TRANSCRIPT_ARGS=()
if [[ "${ORIVYN_REQUIRE_NATIVE_TRANSCRIPT_ROUTE:-0}" == 1 ]]; then
 [[ "$GATE_KIND" == reviewed-plan && " $ORIVYN_NATIVE_FEATURES " == *' ORIVYN_NATIVE_TRANSCRIPT '* ]] || { echo 'Native transcript proof needs reviewed-plan and its build flag.' >&2; exit 2; }
 TRANSCRIPT_ARGS+=(--require-native-transcript)
fi
python3 "$ROOT/Diagnostics/NativeTools/simulator_gate.py" --scheme "$SCHEME" \
 --models "$ORIVYN_NATIVE_TOOLS_MODEL_DIR" --destination "$NATIVE_TOOLS_DESTINATION" \
 --model-id "$MODEL_ID" --gate "$GATE_KIND" "${TRANSCRIPT_ARGS[@]}" > "$NATIVE_TOOLS_EVIDENCE_DIR/gate-config.json"
case "$GATE_KIND" in
 completion) SELECTOR='JarvisEVOTests/ProductionCompletionContractTests/testRequiredApprovedCallsBeforeGroundedAnswer'; DEFAULT_ALLOWANCE=840; MAX_ALLOWANCE=840 ;;
 native-tools) SELECTOR='JarvisEVOTests/ProductionNativeToolsRuntimeTests/testRequiredProductionSuggestionAndReload'; DEFAULT_ALLOWANCE=300; MAX_ALLOWANCE=600 ;;
 reviewed-plan) SELECTOR='JarvisEVOTests/ProductionReviewedReadPlanTests/testRequiredModelProposalApprovalAndGroundedRead'; DEFAULT_ALLOWANCE=1200; MAX_ALLOWANCE=1200 ;;
 local-agent) SELECTOR='JarvisEVOTests/ProductionLocalAgentSessionTests/testRequiredSearchThenReadGroundedAnswer'; DEFAULT_ALLOWANCE=840; MAX_ALLOWANCE=840 ;;
 *) echo 'Unknown required gate' >&2; exit 2 ;;
esac

sysctl hw.memsize > "$NATIVE_TOOLS_EVIDENCE_DIR/host-memory.txt"
vm_stat > "$NATIVE_TOOLS_EVIDENCE_DIR/host-vm-before.txt"
cd "$ROOT"
set +e
xcodebuild test -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -destination "$NATIVE_TOOLS_DESTINATION" -destination-timeout 120 \
 -derivedDataPath "$NATIVE_TOOLS_DERIVED_DATA" \
 -parallel-testing-enabled NO -enableCodeCoverage NO \
 "-only-testing:$SELECTOR" \
 -test-timeouts-enabled YES -default-test-execution-time-allowance "$DEFAULT_ALLOWANCE" \
 -maximum-test-execution-time-allowance "$MAX_ALLOWANCE" \
 -resultBundlePath "$NATIVE_TOOLS_EVIDENCE_DIR/ProductionNativeTools.xcresult" \
 "ORIVYN_NATIVE_FEATURES=$ORIVYN_NATIVE_FEATURES" CODE_SIGNING_ALLOWED=NO \
 2>&1 | tee "$NATIVE_TOOLS_EVIDENCE_DIR/xcodebuild.log"
PIPE_STATUSES=("${PIPESTATUS[@]}")
BUILD_STATUS=${PIPE_STATUSES[0]}
LOG_STATUS=${PIPE_STATUSES[1]}
# Preserve failure attachments and summaries too; never let a later success hide a failed build.
xcrun xcresulttool export attachments --path "$NATIVE_TOOLS_EVIDENCE_DIR/ProductionNativeTools.xcresult" --output-path "$NATIVE_TOOLS_EVIDENCE_DIR/attachments"
ATTACHMENT_STATUS=$?
xcrun xcresulttool get test-results summary --path "$NATIVE_TOOLS_EVIDENCE_DIR/ProductionNativeTools.xcresult" > "$NATIVE_TOOLS_EVIDENCE_DIR/test-summary.json"
SUMMARY_STATUS=$?
python3 Diagnostics/NativeTools/verify_simulator_result.py "$NATIVE_TOOLS_EVIDENCE_DIR/test-summary.json"
VERIFY_STATUS=$?
set -e
printf 'xcodebuild=%s\nlog=%s\nattachments=%s\nsummary=%s\nverifier=%s\n' "$BUILD_STATUS" "$LOG_STATUS" "$ATTACHMENT_STATUS" "$SUMMARY_STATUS" "$VERIFY_STATUS" > "$NATIVE_TOOLS_EVIDENCE_DIR/outcomes.txt"
[[ "$BUILD_STATUS" == 0 && "$LOG_STATUS" == 0 && "$ATTACHMENT_STATUS" == 0 && "$SUMMARY_STATUS" == 0 && "$VERIFY_STATUS" == 0 ]]
