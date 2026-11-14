#!/usr/bin/env bash
# Explicit parent-invoked gate. No CI dispatch, framework build, download, signing,
# simulator boot/selection or tracked project change occurs in this script.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'This gate requires the authorized Mac runner.' >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${ORIVYN_VISION_MODEL_DIR:?Absolute directory prepared with prepare_production_pair.py}"
: "${ORIVYN_NATIVE_FEATURES:?Combined runtime feature flags including ORIVYN_NATIVE_VISION}"
[[ " $ORIVYN_NATIVE_FEATURES " == *' ORIVYN_NATIVE_VISION '* ]] || { echo 'Native vision build flag required.' >&2; exit 2; }
: "${VISION_DESTINATION:?Existing platform=iOS Simulator,id=... destination}"
: "${VISION_DERIVED_DATA:?Shared absolute DerivedData path for this gate and full tests}"
: "${VISION_EVIDENCE_DIR:?New absolute evidence directory}"
[[ "$ORIVYN_VISION_MODEL_DIR" == /* && "$VISION_DERIVED_DATA" == /* && "$VISION_EVIDENCE_DIR" == /* ]] || { echo 'Paths must be absolute.' >&2; exit 2; }
SCHEME="$ROOT/JarvisEVO.xcodeproj/xcshareddata/xcschemes/JarvisEVO.xcscheme"
[[ -f "$SCHEME" ]] || { echo 'Generate the main project with the combined runtime flags first.' >&2; exit 2; }
mkdir "$VISION_EVIDENCE_DIR"
cp "$SCHEME" "$VISION_EVIDENCE_DIR/original.xcscheme"
cleanup() {
 vm_stat > "$VISION_EVIDENCE_DIR/host-vm-after.txt" || true
 cp "$VISION_EVIDENCE_DIR/original.xcscheme" "$SCHEME"
}
trap cleanup EXIT
# Environment must reach the test-host process, not just the xcodebuild shell.
# Patch only the generated scheme and restore it even when xcodebuild fails.
python3 - "$SCHEME" "$ORIVYN_VISION_MODEL_DIR" <<'PY'
import sys, xml.etree.ElementTree as ET
from pathlib import Path
scheme, models = sys.argv[1:]
if not Path(models).is_dir(): raise SystemExit('Required fixture directory missing')
tree = ET.parse(scheme); action = tree.getroot().find('TestAction')
if action is None: raise SystemExit('Main scheme has no TestAction')
action.set('shouldUseLaunchSchemeArgsEnv', 'NO')
variables = action.find('EnvironmentVariables')
if variables is None: variables = ET.SubElement(action, 'EnvironmentVariables')
for key,value in [('ORIVYN_REQUIRE_PRODUCTION_VISION','1'),('ORIVYN_VISION_MODEL_DIR',models)]:
    for existing in list(variables):
        if existing.get('key') == key: variables.remove(existing)
    ET.SubElement(variables,'EnvironmentVariable',key=key,value=value,isEnabled='YES')
tree.write(scheme, encoding='UTF-8', xml_declaration=True)
PY
sysctl hw.memsize > "$VISION_EVIDENCE_DIR/host-memory.txt"
vm_stat > "$VISION_EVIDENCE_DIR/host-vm-before.txt"
cd "$ROOT"
xcodebuild test -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -destination "$VISION_DESTINATION" -destination-timeout 120 \
 -derivedDataPath "$VISION_DERIVED_DATA" \
 -parallel-testing-enabled NO -enableCodeCoverage NO \
 -only-testing:JarvisEVOTests/ProductionVisionRuntimeTests/testRequiredProductionPNGInferenceAndRelease \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
 -maximum-test-execution-time-allowance 600 \
 -resultBundlePath "$VISION_EVIDENCE_DIR/ProductionVision.xcresult" \
 "ORIVYN_NATIVE_FEATURES=$ORIVYN_NATIVE_FEATURES" CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$VISION_EVIDENCE_DIR/xcodebuild.log"
xcrun xcresulttool export attachments --path "$VISION_EVIDENCE_DIR/ProductionVision.xcresult" --output-path "$VISION_EVIDENCE_DIR/attachments"
python3 - "$VISION_EVIDENCE_DIR/xcodebuild.log" <<'PY_CHECK'
import sys
from pathlib import Path
if 'ORIVYN_PRODUCTION_VISION_REQUIRED_GATE_COMPLETED' not in Path(sys.argv[1]).read_text(errors='replace'):
    raise SystemExit('Required vision gate did not execute to completion; a skip is not acceptance')
PY_CHECK
