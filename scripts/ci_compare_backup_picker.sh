#!/bin/bash
# One hosted simulator, two pinned source revisions, no device resets or publication.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/comparison-baseline"
CAND="$ROOT/comparison-candidate"
OUT="$ROOT/artifacts/picker-comparison"
mkdir -p "$OUT"
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
test "$(git -C "$BASE" rev-parse HEAD)" = a7bb85d2b7974bd6853306ae051f52366a30332a
test "$(git -C "$CAND" rev-parse HEAD)" = 1939a4737e95b94e135268b6efbec2a6f39f6fa2
cmp "$BASE/UITests/JarvisEVOUITests.swift" "$CAND/UITests/JarvisEVOUITests.swift"
command -v xcodegen >/dev/null || brew install xcodegen
xcodebuild -version > "$OUT/xcode-version.txt"
for variant in baseline candidate; do
    dir="$ROOT/comparison-$variant"
    git -C "$dir" rev-parse HEAD > "$OUT/$variant-source.txt"
    python3 "$ROOT/scripts/instrument_backup_picker.py" "$dir"
    git -C "$dir" diff > "$OUT/$variant-instrumentation.patch"
    shasum -a 256 "$dir/UITests/JarvisEVOUITests.swift" > "$OUT/$variant-test-hash.txt"
    (cd "$dir"; python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img; bash scripts/bootstrap_llama.sh; python3 scripts/download_test_model.py > "$OUT/$variant-model-path.txt"; python3 scripts/generate_project.py)
done
cmp "$BASE/.cache/test-models/qwen2.5-0.5b-instruct-q4_k_m.gguf" "$CAND/.cache/test-models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
shasum -a 256 "$BASE/.cache/test-models/qwen2.5-0.5b-instruct-q4_k_m.gguf" "$CAND/.cache/test-models/qwen2.5-0.5b-instruct-q4_k_m.gguf" > "$OUT/model-hashes.txt"
cmp "$BASE/UITests/JarvisEVOUITests.swift" "$CAND/UITests/JarvisEVOUITests.swift"
xcrun simctl list devices available -j > "$OUT/simulators.json"
SIMULATOR_ID=$(python3 "$ROOT/scripts/select_picker_runtime.py" "$OUT/simulators.json")
python3 "$ROOT/scripts/boot_ci_simulator.py" --simulator "$SIMULATOR_ID" --timeout 300 --evidence "$OUT/boot.json"
run_variant() {
    local variant=$1 label=$2 dir="$ROOT/comparison-$1"
    mkdir -p "$OUT/$label"
    set +e
    (cd "$dir"; xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO \
      -derivedDataPath "$OUT/derived-$variant" \
      -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
      -parallel-testing-enabled NO -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 \
      -only-testing:JarvisEVOUITests/JarvisEVOUITests/testHistoryImportCancellationReturnsToSettingsAndPreservesComposer \
      -resultBundlePath "$OUT/$label/Tests.xcresult" CODE_SIGNING_ALLOWED=NO test) \
      > "$OUT/$label/xcodebuild.log" 2>&1
    status=$?
    printf '%s\n' "$status" > "$OUT/$label/exit.txt"
    xcrun xcresulttool get test-results summary --path "$OUT/$label/Tests.xcresult" > "$OUT/$label/summary.json"
    xcrun xcresulttool export attachments --path "$OUT/$label/Tests.xcresult" --output-path "$OUT/$label/attachments"
    xcrun simctl spawn "$SIMULATOR_ID" log show --last 15m --style compact --predicate 'process == "JarvisEVO"' > "$OUT/$label/app-system.log" 2>&1
    set -e
    python3 - "$OUT/$label" <<'PY'
import json,sys,pathlib
p=pathlib.Path(sys.argv[1])
try:
 s=json.loads((p/'summary.json').read_text())
 if s.get('totalTestCount') != 1: raise ValueError('Expected exactly one executed test')
 verdict='pass' if s.get('totalTestCount')==1 and s.get('passedTests')==1 and s.get('failedTests')==0 and s.get('skippedTests')==0 and (p/'exit.txt').read_text().strip()=='0' else 'fail'
except (ValueError,OSError): verdict='infrastructure'
(p/'verdict.txt').write_text(verdict+'\n')
print(p.name,verdict)
PY
}
run_variant baseline A1
run_variant candidate B1
# At most one reverse-order pair; no retry if both failed/shared infrastructure.
pair="$(cat "$OUT/A1/verdict.txt")/$(cat "$OUT/B1/verdict.txt")"
if [[ "$pair" == pass/fail || "$pair" == fail/pass ]]; then
    run_variant candidate B2
    run_variant baseline A2
fi
printf '%s\n' 'Controlled simulator diagnosis only. No external provider, device, release, or replacement-success acceptance.' > "$OUT/SCOPE.txt"
# Explicitly fail if either initial UI result failed; retain every attempt.
grep -qx pass "$OUT/A1/verdict.txt" && grep -qx pass "$OUT/B1/verdict.txt"
