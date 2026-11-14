import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('combined', ROOT / 'scripts/verify_combined_runtime.py')
combined = importlib.util.module_from_spec(spec)
spec.loader.exec_module(combined)

class CombinedAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.libs = []
        for name, variant, arches in [('ios-arm64', None, ['arm64']),
                                     ('ios-arm64_x86_64-simulator', 'simulator', ['arm64', 'x86_64'])]:
            item = dict(LibraryIdentifier=name, LibraryPath='llama.framework', SupportedPlatform='ios', SupportedArchitectures=arches)
            if variant: item['SupportedPlatformVariant'] = variant
            self.libs.append(item)
            fw = self.root / name / 'llama.framework'
            (fw / 'Headers').mkdir(parents=True)
            (fw / 'Modules').mkdir()
            for header in ['llama.h', 'mtmd.h', 'mtmd-helper.h', 'orivyn-tools.h', 'orivyn-vision.h']:
                (fw / 'Headers' / header).write_text('// fixture\n')
            (fw / 'Modules/module.modulemap').write_text('header "orivyn-tools.h"\nheader "orivyn-vision.h"\n')
            (fw / 'llama').write_bytes(b'fixture, not a Mach-O')
        self.write_info()

    def write_info(self):
        (self.root / 'Info.plist').write_bytes(plistlib.dumps({'AvailableLibraries': self.libs}))

    def test_metadata_inspection_does_not_claim_binary_acceptance(self):
        self.assertEqual(len(combined.inspect(self.root)), 2)

    def test_duplicate_platform_cannot_replace_simulator(self):
        self.libs[1] = dict(self.libs[0]); self.write_info()
        with self.assertRaises(ValueError): combined.inspect(self.root)

    def test_missing_simulator_architecture_rejected(self):
        self.libs[1]['SupportedArchitectures'] = ['arm64']; self.write_info()
        with self.assertRaises(ValueError): combined.inspect(self.root)

    def test_external_slice_path_rejected(self):
        self.libs[0]['LibraryIdentifier'] = '../outside'; self.write_info()
        with self.assertRaises(ValueError): combined.inspect(self.root)

    def test_stock_framework_without_bridge_header_rejected(self):
        (self.root / 'ios-arm64/llama.framework/Headers/orivyn-tools.h').unlink()
        with self.assertRaises(ValueError): combined.inspect(self.root)

    def test_unexported_vision_api_rejected(self):
        (self.root / 'ios-arm64/llama.framework/Modules/module.modulemap').write_text('header "orivyn-tools.h"')
        with self.assertRaises(ValueError): combined.inspect(self.root)

class MachOAdmissionTests(unittest.TestCase):
    def commands(self, platform='2', minimum='17.0'):
        return f'Load command 0\n      cmd LC_BUILD_VERSION\n platform {platform}\n    minos {minimum}\n'

    def test_correct_device_and_simulator(self):
        combined.verify_load_commands(self.commands(), None)
        combined.verify_load_commands(self.commands('7'), 'simulator')

    def test_macos_binary_in_claimed_ios_slice_rejected(self):
        with self.assertRaises(ValueError): combined.verify_load_commands(self.commands('1'), None)

    def test_simulator_binary_in_device_slice_rejected(self):
        with self.assertRaises(ValueError): combined.verify_load_commands(self.commands('7'), None)

    def test_newer_minimum_os_rejected(self):
        with self.assertRaises(ValueError): combined.verify_load_commands(self.commands(minimum='17.1'), None)

    def test_missing_or_ambiguous_platform_rejected(self):
        for value in ['', self.commands() + self.commands()]:
            with self.assertRaises(ValueError): combined.verify_load_commands(value, None)

if __name__ == '__main__': unittest.main()
