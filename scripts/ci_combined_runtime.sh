#!/bin/bash
# Build exact upstream and both reviewed bridges on a standard GitHub Mac runner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS required'; exit 2; }
: "${RUNNER_TEMP:?GitHub runner temporary directory required}"
: "${GITHUB_ENV:?GitHub environment output required}"
COMMIT=2496f9c14965c39589f53eea31bdb6d762b1d360
ARTIFACTS="$ROOT/artifacts/combined-runtime"
CACHE="$ROOT/.cache/orivyn-combined"
ARCHIVE="$CACHE/runtime.zip"
mkdir -p "$ARTIFACTS" "$CACHE"
trap 'status=$?; if [[ "$status" != 0 && -f "$ARTIFACTS/build.log" ]]; then tail -n 180 "$ARTIFACTS/build.log"; fi; exit "$status"' EXIT
if [[ -f "$ARCHIVE" && -f "$CACHE/sha256.txt" ]]; then
  HASH="$(cat "$CACHE/sha256.txt")"
  [[ "$HASH" =~ ^[a-f0-9]{64}$ ]]
  [[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" == "$HASH" ]]
  CHECK="$(mktemp -d "$RUNNER_TEMP/orivyn-cache-check.XXXXXX")"
  unzip -q "$ARCHIVE" -d "$CHECK"
  python3 "$ROOT/scripts/verify_combined_runtime.py" "$CHECK/llama.xcframework" | tee "$ARTIFACTS/admission.txt"
  printf '%s\n' 'Exact compiler/source-keyed runtime cache verified; no rebuild.' > "$ARTIFACTS/cache.txt"
else
SOURCE="$(mktemp -d "$RUNNER_TEMP/orivyn-llama.XXXXXX")"
git -C "$SOURCE" init
git -C "$SOURCE" remote add origin https://github.com/ggml-org/llama.cpp.git
git -C "$SOURCE" fetch --depth 1 origin "$COMMIT"
git -C "$SOURCE" checkout --detach FETCH_HEAD
[[ "$(git -C "$SOURCE" rev-parse HEAD)" == "$COMMIT" ]]
command -v cmake >/dev/null || brew install cmake
python3 "$ROOT/Diagnostics/CombinedRuntime/prepare_build.py"
export ORIVYN_BRIDGE_ROOT="$ROOT"
(cd "$SOURCE" && bash "$ROOT/Diagnostics/CombinedRuntime/build-ios-combined.sh") > "$ARTIFACTS/build.log" 2>&1
FRAMEWORK="$SOURCE/build-apple/llama.xcframework"
python3 "$ROOT/scripts/verify_combined_runtime.py" "$FRAMEWORK" | tee "$ARTIFACTS/admission.txt"
(cd "$SOURCE/build-apple" && zip -qry "$ARCHIVE" llama.xcframework)
HASH="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
printf '%s\n' "$HASH" > "$CACHE/sha256.txt"
fi
printf '%s  %s\n' "$HASH" 'orivyn-combined-runtime.zip' > "$ARTIFACTS/SHA256SUMS"
printf '%s\n' "$COMMIT" > "$ARTIFACTS/upstream-commit.txt"
git -C "$ROOT" rev-parse HEAD > "$ARTIFACTS/app-source-commit.txt"
printf 'ORIVYN_COMBINED_RUNTIME_ARCHIVE=%s\nORIVYN_COMBINED_RUNTIME_SHA256=%s\n' "$ARCHIVE" "$HASH" >> "$GITHUB_ENV"
