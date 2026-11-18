#!/bin/bash
# Public, synthetic-only focused diagnostic. Never packages or publishes an IPA/release.
set -euo pipefail
cd "$(dirname "$0")/.."
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
: "${RUNNER_TEMP:?}"
A="$PWD/artifacts/files-cold-start-diagnostic"; mkdir -p "$A"
git rev-parse HEAD > "$A/source-commit.txt"
printf '%s\n' 'DIAGNOSTIC ONLY: one cold-start Files ZIP selection test and unified logs. Not the 319-test acceptance gate. No packaging, publication, private data or physical-device verification.' > "$A/SCOPE.txt"
# Preserve the baseline extractor check; this is still not full acceptance.
swift test --jobs 2 --package-path Packages/ArchiveExtraction > "$A/extractor-package.log" 2>&1
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
command -v xcodegen >/dev/null || brew install xcodegen
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$A/test-model-path.txt"
MODEL_DIR="$RUNNER_TEMP/orivyn-conversation-model"
mkdir -p "$MODEL_DIR"
python3 Diagnostics/NativeTools/download.py --model-id qwen3-1.7b-q4_k_m --output "$MODEL_DIR/Qwen3-1.7B-Q4_K_M.gguf" > "$A/conversation-model-path.txt"
python3 scripts/make_import_resource_fixtures.py --output .cache/test-archives
python3 scripts/generate_project.py
python3 - "$MODEL_DIR" <<'PYENV'
import pathlib, sys, xml.etree.ElementTree as ET
p=pathlib.Path('JarvisEVO.xcodeproj/xcshareddata/xcschemes/JarvisEVO.xcscheme')
tree=ET.parse(p); action=tree.getroot().find('TestAction'); assert action is not None
env=action.find('EnvironmentVariables')
if env is None: env=ET.SubElement(action,'EnvironmentVariables')
values={'ORIVYN_REQUIRE_NORMAL_CHAT_MODEL':'1','ORIVYN_REQUIRE_CONVERSATION_MODEL':'1','ORIVYN_PRODUCTION_MODEL_ID':'qwen3-1.7b-q4_k_m','ORIVYN_CONVERSATION_MODEL_DIR':str(pathlib.Path(sys.argv[1]).resolve())}
for key,value in values.items():
 for old in list(env):
  if old.get('key')==key: env.remove(old)
 ET.SubElement(env,'EnvironmentVariable',key=key,value=value,isEnabled='YES')
tree.write(p,encoding='UTF-8',xml_declaration=True)
assert all(any(e.get('key')==k and e.get('value')==v and e.get('isEnabled')=='YES' for e in env) for k,v in values.items())
PYENV
xcrun simctl list devices available -j > "$A/simulators.json"
SIM=$(python3 scripts/select_reviewed_runtime.py "$A/simulators.json")
python3 scripts/boot_ci_simulator.py --simulator "$SIM" --timeout 300 --evidence "$A/boot.json"
# The fresh hosted runner has a disposable simulator; never open Files to warm it.
LOG_PREDICATE='process == "JarvisEVO" OR process CONTAINS[c] "fileprovider" OR subsystem CONTAINS[c] "fileprovider" OR subsystem CONTAINS[c] "documentmanager" OR process CONTAINS[c] "DocumentManager"'
xcrun simctl spawn "$SIM" log stream --style compact --level debug --predicate "$LOG_PREDICATE" > "$A/files-unified-stream.log" 2>&1 &
LOG_PID=$!
cleanup_logs() {
 kill "$LOG_PID" 2>/dev/null || true
 wait "$LOG_PID" 2>/dev/null || true
}
trap cleanup_logs EXIT
ARCHIVE_RESTORE_SIMULATOR="$SIM" bash Diagnostics/ArchiveRestore/prepare_fixture.sh > "$A/provider-fixture.log" 2>&1
set +e
xcodebuild test -project JarvisEVO.xcodeproj -scheme JarvisEVO -derivedDataPath "$RUNNER_TEMP/orivyn-files-diagnostic-derived" \
 -destination "platform=iOS Simulator,id=$SIM" -destination-timeout 120 -parallel-testing-enabled NO \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 194 -maximum-test-execution-time-allowance 750 \
 -only-testing:JarvisEVOUITests/ArchiveRestoreUITests/testActualZIPSelectionReviewCommitAndRelaunchHistory \
 -resultBundlePath "$A/Tests.xcresult" CODE_SIGNING_ALLOWED=NO > "$A/xcodebuild.log" 2>&1
status=$?
printf '%s\n' "$status" > "$A/xcodebuild-exit.txt"
if kill -0 "$LOG_PID" 2>/dev/null; then echo running; else echo exited-early; fi > "$A/log-stream-state.txt"
cleanup_logs
trap - EXIT
xcrun simctl spawn "$SIM" log show --last 30m --style compact --info --debug --predicate "$LOG_PREDICATE" > "$A/files-unified-history.log" 2>&1
printf '%s\n' "$?" > "$A/log-history-exit.txt"
set -e
if test -d "$A/Tests.xcresult"; then
 xcrun xcresulttool get test-results summary --path "$A/Tests.xcresult" > "$A/summary.json"
 xcrun xcresulttool export attachments --path "$A/Tests.xcresult" --output-path "$A/attachments"
fi
# Preserve failed status, even when logs were collected successfully.
test "$status" = 0 || exit "$status"
python3 - "$A/summary.json" <<'PYDIAGNOSTIC'
import json, sys
s = json.load(open(sys.argv[1]))
for key, expected in {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0}.items():
    assert type(s.get(key)) is int and s[key] == expected, (key, s.get(key), expected)
print('One focused diagnostic test passed; NOT full native acceptance or release readiness.')
PYDIAGNOSTIC
