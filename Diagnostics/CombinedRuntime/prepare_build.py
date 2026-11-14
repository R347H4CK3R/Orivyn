"""Generate the unexecuted Apple combined-runtime recipe from pinned upstream."""
import importlib.util
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('vision_recipe', ROOT / 'VisionRuntime/prepare_build.py')
vision = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vision)

def transform(source):
    result = vision.transform(source)  # exact upstream digest required
    result = result.replace('[[ \"$(uname -s)\" == Darwin ]] || exit 1',
                            '[[ \"$(uname -s)\" == Darwin ]] || exit 1\ngit diff --quiet && git diff --cached --quiet || exit 1', 1)
    result = result.replace('# Options', ': "${ORIVYN_BRIDGE_ROOT:?reviewed app source is required}"\n# Options', 1)
    result = result.replace('COMMON_CMAKE_ARGS=(', '''COMMON_CMAKE_ARGS=(
    "-DCMAKE_PROJECT_INCLUDE=$ORIVYN_BRIDGE_ROOT/Diagnostics/CombinedRuntime/native-bridges.cmake"
    -DLLAMA_BUILD_COMMON=ON
    -DLLAMA_OPENSSL=OFF
    -DLLAMA_BUILD_BORINGSSL=OFF
    -DLLAMA_BUILD_LIBRESSL=OFF
    -DLLAMA_LLGUIDANCE=OFF
    -DGGML_BACKEND_DL=OFF''', 1)
    result = result.replace('--target mtmd', '--target orivyn-bridges')
    result = result.replace('    cp tools/mtmd/mtmd.h', '''    cp "$ORIVYN_BRIDGE_ROOT/Diagnostics/NativeTools/bridge.h" "${header_path}/orivyn-tools.h"
    cp "$ORIVYN_BRIDGE_ROOT/Diagnostics/VisionProof/Bridge/vision_bridge.h" "${header_path}/orivyn-vision.h"
    cp tools/mtmd/mtmd.h''', 1)
    result = result.replace('    header "llama.h"', '    header "llama.h"\n    header "orivyn-tools.h"\n    header "orivyn-vision.h"', 1)
    result = result.replace('    local libs=(', '''    local libs=(
        "${base_dir}/${build_dir}/${release_dir}/liborivyn-bridges.a"
        "${base_dir}/${build_dir}/common/${release_dir}/libllama-common.a"
        "${base_dir}/${build_dir}/common/${release_dir}/libllama-common-base.a"
        "${base_dir}/${build_dir}/vendor/cpp-httplib/${release_dir}/libcpp-httplib.a"''', 1)
    return result

if __name__ == '__main__':
    (ROOT / 'CombinedRuntime/build-ios-combined.sh').write_text(
        transform((ROOT / 'VisionRuntime/source/build-xcframework.sh').read_text()))
