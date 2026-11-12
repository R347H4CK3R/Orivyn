"""Generate (do not execute) an iOS-only b9049 runtime recipe from audited upstream."""
import hashlib,pathlib
COMMIT='2496f9c14965c39589f53eea31bdb6d762b1d360'
EXPECTED='d6c19abdc61778bee389fa31237d4c3d0cfdc1f7512dc17466b9843c2ea7ce82'
def transform(s):
 if hashlib.sha256(s.encode()).hexdigest()!=EXPECTED: raise ValueError('unexpected upstream build script')
 s=s.replace('# Options', f'''# Requires an isolated full source checkout at the exact b9049 commit.
set -euo pipefail
[[ "$(git rev-parse HEAD)" == "{COMMIT}" ]] || exit 1
[[ "$(uname -s)" == Darwin ]] || exit 1
# Options''',1)
 for platform in ['macos','visionos','visionos-sim','tvos-sim','tvos-device']:
  s=s.replace('rm -rf build-'+platform+'\n','')
 s=s.replace('LLAMA_BUILD_TOOLS=OFF','LLAMA_BUILD_TOOLS=ON',1)
 s=s.replace('IOS_MIN_OS_VERSION=16.4','IOS_MIN_OS_VERSION=17.0',1)
 s=s.replace('    cp include/llama.h', '    cp tools/mtmd/mtmd.h ${header_path}\n    cp tools/mtmd/mtmd-helper.h ${header_path}\n    cp include/llama.h',1)
 s=s.replace('    header "llama.h"','    header "llama.h"\n    header "mtmd.h"\n    header "mtmd-helper.h"',1)
 s=s.replace('    local libs=(','    local libs=(\n        "${base_dir}/${build_dir}/tools/mtmd/${release_dir}/libmtmd.a"',1)
 s=s[:s.index('echo "Building for macOS..."')]
 s=s.replace('--config Release -- -quiet','--config Release --target mtmd --parallel 2 -- -quiet')
 s+='''
# Exactly one combined llama framework per platform; do not also link old release.
setup_framework_structure "build-ios-sim" ${IOS_MIN_OS_VERSION} "ios"
setup_framework_structure "build-ios-device" ${IOS_MIN_OS_VERSION} "ios"
combine_static_libraries "build-ios-sim" "Release-iphonesimulator" "ios" "true"
combine_static_libraries "build-ios-device" "Release-iphoneos" "ios" "false"
xcrun xcodebuild -create-xcframework \\
    -framework "$(pwd)/build-ios-sim/framework/llama.framework" \\
    -debug-symbols "$(pwd)/build-ios-sim/dSYMs/llama.dSYM" \\
    -framework "$(pwd)/build-ios-device/framework/llama.framework" \\
    -debug-symbols "$(pwd)/build-ios-device/dSYMs/llama.dSYM" \\
    -output "$(pwd)/build-apple/llama.xcframework"
# Packaging/symbol smoke tests and archive hash recording still required before use.
'''
 return s
if __name__=='__main__':
 root=pathlib.Path(__file__).resolve().parent
 (root/'build-ios-mtmd.sh').write_text(transform((root/'source/build-xcframework.sh').read_text()))
