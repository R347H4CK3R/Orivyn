import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('verify_ipa', Path(__file__).resolve().parents[1] / 'verify_ipa.py')

class IPAValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def load(self):
        self.assertTrue(Path(SPEC.origin).is_file(), 'IPA validator has not been implemented')
        module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(module)
        return module
    def make(self, *, arch=0x0100000C, minimum=26, platform=2, missing=False, traversal=False, empty=False, framework_min=None, framework_kind=6, build="1", binary_suffix=b""):
        out = self.root / 'test.ipa'
        command = struct.pack('<6I', 0x32, 24, platform, minimum << 16, 26 << 16, 0)
        ncmds = 1
        if framework_min is not None:
            name = b'@rpath/llama.framework/llama\0'
            size = (24 + len(name) + 7) // 8 * 8
            command += struct.pack('<6I', 0xC, size, 24, 0, 0, 0) + name + b'\0' * (size - 24 - len(name))
            ncmds += 1
        binary = struct.pack('<8I', 0xFEEDFACF, arch, 0, 2, ncmds, len(command), 0, 0) + command + binary_suffix
        info = {'CFBundleExecutable':'JarvisEVO','CFBundleIdentifier':'app.jarvisevo.ios','CFBundleName':'JarvisEVO','CFBundleShortVersionString':'0.1.0','CFBundleVersion':build,'MinimumOSVersion':'26.0','CFBundleSupportedPlatforms':['iPhoneOS']}
        with zipfile.ZipFile(out, 'w') as z:
            z.writestr('Payload/JarvisEVO.app/Info.plist', plistlib.dumps(info))
            z.writestr('Payload/JarvisEVO.app/Assets.car', b'fixture-assets')
            if not missing: z.writestr('Payload/JarvisEVO.app/JarvisEVO', b'' if empty else binary)
            if traversal: z.writestr('../../outside', b'bad')
            if framework_min is not None:
                version = struct.pack('<6I', 0x32, 24, 2, framework_min << 16, 26 << 16, 0)
                framework = struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, framework_kind, 1, 24, 0, 0) + version
                z.writestr('Payload/JarvisEVO.app/Frameworks/llama.framework/llama', framework)
        return out
    def test_valid_arm64_device_fixture(self):
        result = self.load().verify(self.make())
        self.assertEqual(result['architecture'], 'arm64')
        self.assertEqual(result['minimum_ios'], '26.0')
        self.assertEqual(len(result['sha256']), 64)
    def test_missing_executable_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(missing=True))
    def test_empty_executable_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(empty=True))
    def test_x86_binary_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(arch=0x01000007))
    def test_simulator_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(platform=7))
    def test_older_deployment_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(minimum=18))
    def test_path_traversal_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(traversal=True))
    def test_framework_newer_than_app_floor_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(framework_min=27))
    def test_framework_non_dylib_rejected(self):
        with self.assertRaises(ValueError): self.load().verify(self.make(framework_min=17, framework_kind=2))
    def test_compatible_framework_accepted(self):
        self.assertEqual(len(self.load().verify(self.make(framework_min=17))['frameworks']), 1)
    def test_dot_component_alias_rejected(self):
        path=self.make()
        with zipfile.ZipFile(path,'a') as archive: archive.writestr('Payload/JarvisEVO.app/./JarvisEVO',b'bad')
        with self.assertRaises(ValueError): self.load().verify(path)
    def test_repeated_separator_alias_rejected(self):
        path=self.make()
        with zipfile.ZipFile(path,'a') as archive: archive.writestr('Payload/JarvisEVO.app//JarvisEVO',b'bad')
        with self.assertRaises(ValueError): self.load().verify(path)
    def test_case_collision_rejected(self):
        path=self.make()
        with zipfile.ZipFile(path,'a') as archive: archive.writestr('Payload/JarvisEVO.app/jarvisevo',b'bad')
        with self.assertRaises(ValueError): self.load().verify(path)
    def test_renamed_zip_rejected(self):
        path = self.root / 'fake.ipa'
        with zipfile.ZipFile(path,'w') as z: z.writestr('README.txt','not an app')
        with self.assertRaises(ValueError): self.load().verify(path)


    def candidate3_resources(self, path, *, missing=None, corrupt=None):
        resources = Path(__file__).resolve().parents[2] / 'JarvisEVO' / 'Resources'
        with zipfile.ZipFile(path, 'a') as archive:
            for name in ('katex-0.19.1.min.js', 'KaTeX-0.19.1-LICENSE.txt'):
                if name != missing:
                    data = (resources / name).read_bytes()
                    archive.writestr('Payload/JarvisEVO.app/' + name, data + (b'changed' if name == corrupt else b''))
        return path

    def test_every_debug_fixture_marker_is_rejected_in_executable_bytes(self):
        markers = ('RootViewRegressionFixture', 'RootViewFixtureProvider', 'root-ui-fixture',
                   '--root-view-fixture', 'CONTROLLED ROOTVIEW FIXTURE')
        for marker in markers:
            for encoding in ('utf-8', 'utf-16-le', 'utf-16-be'):
                with self.subTest(marker=marker, encoding=encoding):
                    path = self.make(binary_suffix=b'\0' + marker.encode(encoding) + b'\0')
                    with self.assertRaisesRegex(ValueError, 'DEBUG fixture marker'):
                        self.load().verify(path)

    def test_normal_uitesting_storage_flag_remains_allowed(self):
        result = self.load().verify(self.make(binary_suffix=b'\0--uitesting\0--reset-test-storage\0'))
        self.assertTrue(result.get('release_fixture_markers_absent'))

    def test_old_build_two_does_not_require_new_candidate_resources(self):
        result = self.load().verify(self.make(build='2'))
        self.assertIs(result.get('candidate3_resources_required'), False)
        self.assertEqual(result.get('bundled_resources'), {})

    def test_build_three_requires_bundled_katex_script(self):
        with self.assertRaisesRegex(ValueError, 'Missing required bundled resource: katex'):
            self.load().verify(self.candidate3_resources(self.make(build='3'), missing='katex-0.19.1.min.js'))

    def test_build_three_requires_bundled_katex_license(self):
        with self.assertRaisesRegex(ValueError, 'Missing required bundled resource: KaTeX'):
            self.load().verify(self.candidate3_resources(self.make(build='3'), missing='KaTeX-0.19.1-LICENSE.txt'))

    def test_changed_katex_script_or_license_is_rejected(self):
        for name in ('katex-0.19.1.min.js', 'KaTeX-0.19.1-LICENSE.txt'):
            with self.subTest(name=name):
                with self.assertRaisesRegex(ValueError, 'Bundled resource SHA-256 mismatch'):
                    self.load().verify(self.candidate3_resources(self.make(build='3'), corrupt=name))

    def test_build_three_and_later_verify_actual_pinned_resource_bytes(self):
        for build in ('3', '3.1', '12'):
            with self.subTest(build=build):
                result = self.load().verify(self.candidate3_resources(self.make(build=build)))
                self.assertTrue(result.get('candidate3_resources_required'))
                self.assertTrue(result.get('release_fixture_markers_absent'))
                self.assertEqual(result.get('bundled_resources'), {
                    'katex-0.19.1.min.js': 'fa140498b8cfc8302cbe5e7cb1bdbc1f952bc38b3fa258ede09e73edbf9a74bc',
                    'KaTeX-0.19.1-LICENSE.txt': '766ccc1f306c885aa45542a9846bbd0a505b27a0374f146778171c2254ce18e3'})

    def test_invalid_build_cannot_bypass_resource_requirement(self):
        for build in ('3-beta', 'three', 3, '３'):
            with self.subTest(build=build):
                with self.assertRaisesRegex(ValueError, 'Invalid app build number'):
                    self.load().verify(self.make(build=build))

    def test_test_only_photo_is_rejected_anywhere_in_shipping_app(self):
        for name in ('OCR-card.png', 'Fixtures/ocr-CARD.PNG'):
            with self.subTest(name=name):
                path = self.make()
                with zipfile.ZipFile(path, 'a') as archive:
                    archive.writestr('Payload/JarvisEVO.app/' + name, b'fixture photo')
                with self.assertRaisesRegex(ValueError, 'Test-only photo fixture'):
                    self.load().verify(path)

    def test_gguf_named_or_renamed_weights_are_rejected_in_shipping_app(self):
        for name, data in (('weights.GGUF', b'weight bytes'), ('Resources/renamed.bin', b'GGUF' + b'weight bytes')):
            with self.subTest(name=name):
                path = self.make()
                with zipfile.ZipFile(path, 'a') as archive:
                    archive.writestr('Payload/JarvisEVO.app/' + name, data)
                with self.assertRaisesRegex(ValueError, 'Bundled GGUF weights'):
                    self.load().verify(path)


    def test_malformed_numeric_builds_cannot_bypass_resource_gate(self):
        # Deliberately resource-free: invalid numeric versions must fail before
        # deciding whether this package predates the renderer.
        for build in ('2.1.1.1', '0.3', '0', '2.0.0.0', '10000', '3.100',
                      '3.0.100', '2.100', '2.1.100', '02', '2.01', '0003'):
            with self.subTest(build=build):
                with self.assertRaisesRegex(ValueError, 'Invalid app build number'):
                    self.load().verify(self.make(build=build))

    def test_supported_shipping_build_grammar_boundaries(self):
        for build in ('1', '2', '2.0', '2.99.99'):
            with self.subTest(build=build):
                result = self.load().verify(self.make(build=build))
                self.assertIs(result['candidate3_resources_required'], False)
        for build in ('3', '3.1', '3.0.0', '9999.99.99'):
            with self.subTest(build=build):
                result = self.load().verify(self.candidate3_resources(self.make(build=build)))
                self.assertIs(result['candidate3_resources_required'], True)
