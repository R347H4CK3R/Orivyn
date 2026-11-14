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
  cp "$NATIVE_TOOLS_EVIDENCE_DIR/original.xcscheme" "$SCHEME" || return 1
  return "$status"
}
trap cleanup EXIT
# TestAction environment is explicit; shell variables alone do not establish
# simulator test-host propagation. Restore the generated scheme on every exit.
python3 - "$SCHEME" "$ORIVYN_NATIVE_TOOLS_MODEL_DIR" "$NATIVE_TOOLS_DESTINATION" <<'PY'
import re, sys, xml.etree.ElementTree as ET
from pathlib import Path
scheme, models, destination = sys.argv[1:]
if not re.fullmatch(r'platform=iOS Simulator,id=[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', destination):
    raise SystemExit('Exactly one explicit simulator UUID is required')
root = Path(models)
model = root / 'Qwen3-1.7B-Q8_0.gguf'
if root.is_symlink() or not root.is_dir() or model.is_symlink() or not model.is_file():
    raise SystemExit('Required regular model fixture is missing; run the pinned downloader first')
tree = ET.parse(scheme); action = tree.getroot().find('TestAction')
if action is None: raise SystemExit('Main scheme has no TestAction')
action.set('shouldUseLaunchSchemeArgsEnv', 'NO')
variables = action.find('EnvironmentVariables')
if variables is None: variables = ET.SubElement(action, 'EnvironmentVariables')
for key, value in [('ORIVYN_REQUIRE_PRODUCTION_NATIVE_TOOLS', '1'), ('ORIVYN_NATIVE_TOOLS_MODEL_DIR', models)]:
    for existing in list(variables):
        if existing.get('key') == key: variables.remove(existing)
    ET.SubElement(variables, 'EnvironmentVariable', key=key, value=value, isEnabled='YES')
tree.write(scheme, encoding='UTF-8', xml_declaration=True)
PY
sysctl hw.memsize > "$NATIVE_TOOLS_EVIDENCE_DIR/host-memory.txt"
vm_stat > "$NATIVE_TOOLS_EVIDENCE_DIR/host-vm-before.txt"
cd "$ROOT"
xcodebuild test -project JarvisEVO.xcodeproj -scheme JarvisEVO \
 -destination "$NATIVE_TOOLS_DESTINATION" -destination-timeout 120 \
 -derivedDataPath "$NATIVE_TOOLS_DERIVED_DATA" \
 -parallel-testing-enabled NO -enableCodeCoverage NO \
 -only-testing:JarvisEVOTests/ProductionNativeToolsRuntimeTests/testRequiredProductionSuggestionAndReload \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
 -maximum-test-execution-time-allowance 600 \
 -resultBundlePath "$NATIVE_TOOLS_EVIDENCE_DIR/ProductionNativeTools.xcresult" \
 "ORIVYN_NATIVE_FEATURES=$ORIVYN_NATIVE_FEATURES" CODE_SIGNING_ALLOWED=NO \
 2>&1 | tee "$NATIVE_TOOLS_EVIDENCE_DIR/xcodebuild.log"
xcrun xcresulttool export attachments --path "$NATIVE_TOOLS_EVIDENCE_DIR/ProductionNativeTools.xcresult" --output-path "$NATIVE_TOOLS_EVIDENCE_DIR/attachments"
xcrun xcresulttool get test-results summary --path "$NATIVE_TOOLS_EVIDENCE_DIR/ProductionNativeTools.xcresult" > "$NATIVE_TOOLS_EVIDENCE_DIR/test-summary.json"
python3 Diagnostics/NativeTools/verify_simulator_result.py "$NATIVE_TOOLS_EVIDENCE_DIR/test-summary.json"
