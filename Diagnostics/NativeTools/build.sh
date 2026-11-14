#!/bin/bash
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
L=${LLAMA_SOURCE:?Set LLAMA_SOURCE to the pinned b9049 source checkout}
B=${LLAMA_BUILD:?Set LLAMA_BUILD to the combined-build llama archive directory}
if [ -e "$L/.git" ]; then
  test "$(git -C "$L" rev-parse HEAD)" = 2496f9c14965c39589f53eea31bdb6d762b1d360
else
  test "${LLAMA_SOURCE_COMMIT:?For an extracted archive, supply its verified commit}" = 2496f9c14965c39589f53eea31bdb6d762b1d360
fi
INCLUDES=(-I"$L/include" -I"$L/common" -I"$L/ggml/include" -I"$L/vendor")
g++ -std=c++17 -shared -fPIC "${INCLUDES[@]}" "$D/bridge.cpp" -Wl,--no-undefined -Wl,--start-group "$B/common/libllama-common.a" "$B/common/libllama-common-base.a" "$B/src/libllama.a" "$B/ggml/src/libggml.a" "$B/ggml/src/libggml-base.a" "$B/ggml/src/libggml-cpu.a" "$B/vendor/cpp-httplib/libcpp-httplib.a" -Wl,--end-group -lpthread -ldl -o "$D/libOwnedNativeGate.so"
g++ -std=c++17 "${INCLUDES[@]}" "$D/driver-tests.cpp" -L"$D" -lOwnedNativeGate -Wl,-rpath,"$D" -lpthread -o "$D/driver-tests"
g++ -std=c++17 -shared -fPIC "${INCLUDES[@]}" "$D/test-shim.cpp" -L"$D" -lOwnedNativeGate -Wl,-rpath,"$D" -o "$D/libtestshim.so"
