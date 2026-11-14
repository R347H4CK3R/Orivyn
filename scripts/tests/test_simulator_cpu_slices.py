"""Execute the simulator orchestration with command doubles; no Apple build claim."""
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'Diagnostics/CombinedRuntime/build-ios-combined.sh').read_text()
START = SOURCE.index('# Configure each simulator slice separately:')
END = SOURCE.index('\necho "Building for iOS devices..."', START)
PREFIX = r'''
set -euo pipefail
COMMON_CMAKE_ARGS=(-DGGML_NATIVE=OFF)
COMMON_C_FLAGS=-g
COMMON_CXX_FLAGS=-g
IOS_MIN_OS_VERSION=17.0
cmake() {
    printf 'cmake %s\n' "$*"
    if [[ "${FAIL_ARCH:-}" != "" && "$*" == *"--build build-ios-sim-${FAIL_ARCH}"* ]]; then return 17; fi
}
setup_framework_structure() { printf 'setup %s\n' "$*"; }
combine_static_libraries() { printf 'link %s\n' "$*"; }
mkdir() { printf 'mkdir %s\n' "$*"; }
cp() { printf 'cp %s\n' "$*"; }
xcrun() { printf 'xcrun %s\n' "$*"; }
'''

class SimulatorSlicesTests(unittest.TestCase):
    def run_recipe(self, failure=''):
        return subprocess.run(['bash', '-c', PREFIX + SOURCE[START:END]], text=True,
                              capture_output=True, env={**os.environ, 'FAIL_ARCH': failure})

    def test_distinct_configurations_link_before_merge(self):
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        config = [line for line in lines if line.startswith('cmake -B ')]
        self.assertEqual(len(config), 2)
        for index, arch in enumerate(('arm64', 'x86_64')):
            self.assertIn(f'-B build-ios-sim-{arch} ', config[index])
            self.assertIn(f'-DCMAKE_OSX_ARCHITECTURES={arch} ', config[index])
            self.assertNotIn(';', config[index])
            self.assertIn('-DCMAKE_OSX_SYSROOT=iphonesimulator', config[index])
            self.assertIn(f'link build-ios-sim-{arch} Release-iphonesimulator ios true {arch}', lines)
        merges = [i for i, line in enumerate(lines) if line.startswith('xcrun lipo -create')]
        self.assertEqual(len(merges), 2)
        self.assertGreater(min(merges), max(i for i, line in enumerate(lines) if line.startswith('link ')))
        self.assertEqual(sum('lipo -verify_arch arm64 x86_64' in line for line in lines), 2)
        self.assertIn('DWARF/llama', lines[merges[1]])

    def test_failed_slice_cannot_package_success(self):
        for arch in ('arm64', 'x86_64'):
            with self.subTest(arch=arch):
                result = self.run_recipe(arch)
                self.assertEqual(result.returncode, 17)
                self.assertNotIn('lipo -create', result.stdout)

    def test_generator_preserves_split_recipe_and_cache_keys(self):
        # Execute the production entry point in a temporary source tree; do not
        # rely on a hand-edited generated artifact surviving CI regeneration.
        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory)
            for relative in ('Diagnostics/CombinedRuntime/prepare_build.py',
                             'Diagnostics/CombinedRuntime/simulator-slices.sh',
                             'Diagnostics/VisionRuntime/prepare_build.py',
                             'Diagnostics/VisionRuntime/source/build-xcframework.sh'):
                target = checkout / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            subprocess.run([sys.executable, str(checkout / 'Diagnostics/CombinedRuntime/prepare_build.py')], check=True)
            generated = (checkout / 'Diagnostics/CombinedRuntime/build-ios-combined.sh').read_text()
            self.assertEqual(generated, SOURCE)
            self.assertNotIn('CMAKE_OSX_ARCHITECTURES="arm64;x86_64"', generated)
            subprocess.run(['bash', '-n'], input=generated, text=True, check=True)
        keys = []
        for filename in ('verify.yml', 'verify-intel.yml'):
            keys.extend(line for line in (ROOT / '.github/workflows' / filename).read_text().splitlines()
                        if 'hashFiles(' in line and 'CombinedRuntime' in line)
        self.assertEqual(len(keys), 3)
        for key in keys:
            for source in ('prepare_build.py', 'simulator-slices.sh', 'build-ios-combined.sh'):
                self.assertIn('Diagnostics/CombinedRuntime/' + source, key)

    def test_device_and_link_contract(self):
        device = SOURCE[END:]
        self.assertIn('-DCMAKE_OSX_ARCHITECTURES="arm64"', device)
        self.assertIn('-DCMAKE_OSX_SYSROOT=iphoneos', device)
        self.assertIn('combine_static_libraries "build-ios-device" "Release-iphoneos" "ios" "false"', device)
        self.assertIn('archs="${simulator_arch:?Simulator linking requires one explicit architecture}"', SOURCE)
        self.assertNotIn('CMAKE_OSX_ARCHITECTURES="arm64;x86_64"', SOURCE)

if __name__ == '__main__':
    unittest.main()
