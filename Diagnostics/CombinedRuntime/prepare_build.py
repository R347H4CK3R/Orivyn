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
    # Keep the architecture fix in the generator, not just its generated output.
    result = result.replace('rm -rf build-ios-sim\n',
                            'rm -rf build-ios-sim build-ios-sim-arm64 build-ios-sim-x86_64\n', 1)
    result = result.replace('local is_simulator="$4"',
                            'local is_simulator="$4"\n    local simulator_arch="${5:-}"', 1)
    result = result.replace('archs="arm64 x86_64"\n                min_version_flag="-mios-simulator',
                            'archs="${simulator_arch:?Simulator linking requires one explicit architecture}"\n                min_version_flag="-mios-simulator', 1)
    start = result.index('echo "Building for iOS simulator..."')
    end = result.index('\necho "Building for iOS devices..."', start)
    result = result[:start] + (ROOT / 'CombinedRuntime/simulator-slices.sh').read_text() + result[end:]
    result = result.replace('setup_framework_structure "build-ios-sim" ${IOS_MIN_OS_VERSION} "ios"\n', '', 1)
    result = result.replace('combine_static_libraries "build-ios-sim" "Release-iphonesimulator" "ios" "true"\n', '', 1)
    result = result.replace("XCODE_VERSION=$(xcrun xcodebuild -version 2>/dev/null | head -n1 | awk '{ print $2 }')", "# Capture complete output: head can close the pipe while xcodebuild is writing.\n# Keep stderr visible so runner/tool failures remain diagnosable.\nXCODE_VERSION_OUTPUT=\"$(xcrun xcodebuild -version)\"\nprintf '%s\\n' \"$XCODE_VERSION_OUTPUT\"\nXCODE_VERSION=\"$(printf '%s\\n' \"$XCODE_VERSION_OUTPUT\" | awk 'NR == 1 { print $2 }')\"", 1)
    return result

if __name__ == '__main__':
    (ROOT / 'CombinedRuntime/build-ios-combined.sh').write_text(
        transform((ROOT / 'VisionRuntime/source/build-xcframework.sh').read_text()))
