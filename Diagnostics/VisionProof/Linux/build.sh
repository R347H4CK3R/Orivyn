#!/usr/bin/env bash
set -euo pipefail
# Explicit existing source/build only: no download, package resolver or server.
SOURCE="${1:?pinned llama.cpp source}"; BUILD="${2:?existing static llama build}"; OUTPUT="${3:?output .so}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
c++ -std=c++17 -O2 -fPIC -shared -DOV_TESTING "$ROOT/Bridge/vision_bridge.cpp" \
  -I"$SOURCE/include" -I"$SOURCE/ggml/include" -I"$SOURCE/tools/mtmd" \
  -Wl,--start-group "$BUILD/tools/mtmd/libmtmd.a" "$BUILD/src/libllama.a" \
  "$BUILD/ggml/src/libggml.a" "$BUILD/ggml/src/libggml-cpu.a" "$BUILD/ggml/src/libggml-base.a" \
  -Wl,--end-group -pthread -ldl -o "$OUTPUT"
