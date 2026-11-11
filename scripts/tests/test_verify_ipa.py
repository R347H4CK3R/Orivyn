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
    def make(self, *, arch=0x0100000C, minimum=26, platform=2, missing=False, traversal=False, empty=False, framework_min=None, framework_kind=6):
        out = self.root / 'test.ipa'
        command = struct.pack('<6I', 0x32, 24, platform, minimum << 16, 26 << 16, 0)
        ncmds = 1
        if framework_min is not None:
            name = b'@rpath/llama.framework/llama\0'
            size = (24 + len(name) + 7) // 8 * 8
            command += struct.pack('<6I', 0xC, size, 24, 0, 0, 0) + name + b'\0' * (size - 24 - len(name))
            ncmds += 1
        binary = struct.pack('<8I', 0xFEEDFACF, arch, 0, 2, ncmds, len(command), 0, 0) + command
        info = {'CFBundleExecutable':'JarvisEVO','CFBundleIdentifier':'app.jarvisevo.ios','CFBundleName':'JarvisEVO','CFBundleShortVersionString':'0.1.0','CFBundleVersion':'1','MinimumOSVersion':'26.0','CFBundleSupportedPlatforms':['iPhoneOS']}
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
