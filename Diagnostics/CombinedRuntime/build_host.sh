#!/usr/bin/env bash
# Linux linkage gate only. Not an Apple framework or a production activation path.
set -euo pipefail
SOURCE="${1:?existing pinned b9049 source}"
BUILD="${2:?static build of that same source}"
OUTPUT="${3:?new output directory}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ ! -e "$OUTPUT" ]] || { echo 'Refusing to overwrite evidence.' >&2; exit 2; }
[[ "$(uname -s)" == Linux ]] || { echo 'Host gate requires Linux.' >&2; exit 2; }
mkdir -p "$OUTPUT"
LIBS=("$BUILD/common/libllama-common.a" "$BUILD/common/libllama-common-base.a"
      "$BUILD/tools/mtmd/libmtmd.a" "$BUILD/src/libllama.a" "$BUILD/ggml/src/libggml.a"
      "$BUILD/ggml/src/libggml-base.a" "$BUILD/ggml/src/libggml-cpu.a"
      "$BUILD/vendor/cpp-httplib/libcpp-httplib.a")
for lib in "${LIBS[@]}"; do [[ -f "$lib" ]] || { echo "Missing archive: $lib" >&2; exit 2; }; done
# One library owns both bridges and one copy of each runtime archive.
# OV_TESTING exposes phase/cancellation probes for this host gate only.
c++ -std=c++17 -fPIC -shared -DOV_TESTING -Wl,--no-undefined \
  -I"$SOURCE/include" -I"$SOURCE/common" -I"$SOURCE/ggml/include" \
  -I"$SOURCE/vendor" -I"$SOURCE/tools/mtmd" \
  "$ROOT/NativeTools/bridge.cpp" "$ROOT/VisionProof/Bridge/vision_bridge.cpp" \
  -Wl,--start-group "${LIBS[@]}" -Wl,--end-group -pthread -ldl \
  -o "$OUTPUT/libOrivynCombined.so"
nm -D --defined-only "$OUTPUT/libOrivynCombined.so" > "$OUTPUT/symbols.txt"
for name in llama_model_load_from_file llama_init_from_model llama_decode mtmd_init_from_file ov3_generate ov4_create_borrowed ov2_create_borrowed ov_run ov_cancel; do
  [[ "$(awk -v symbol="$name" '$3==symbol {n++} END {print n+0}' "$OUTPUT/symbols.txt")" == 1 ]] || { echo "Missing/duplicate ABI: $name" >&2; exit 1; }
done
ldd "$OUTPUT/libOrivynCombined.so" > "$OUTPUT/dependencies.txt"
if grep -E 'lib(llama|ggml|mtmd)' "$OUTPUT/dependencies.txt"; then
  echo 'Unexpected second dynamic model runtime.' >&2; exit 1
fi
sha256sum "$ROOT/NativeTools/bridge.cpp" "$ROOT/NativeTools/bridge.h" \
  "$ROOT/NativeTools/pinned-template.h" "$ROOT/NativeTools/pinned-q4-candidate-template.h" "$ROOT/VisionProof/Bridge/vision_bridge.cpp" \
  "$ROOT/VisionProof/Bridge/vision_bridge.h" "${LIBS[@]}" "$OUTPUT/libOrivynCombined.so" > "$OUTPUT/SHA256SUMS"
echo 'Combined host ABI linked with no undefined symbols or second dynamic model runtime. Apple linking, model quality and device acceptance are NOT verified.'
