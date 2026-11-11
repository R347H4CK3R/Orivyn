from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "ipa_filename.py"


class IPAFilenameTests(unittest.TestCase):
    def run_fixture(self, metadata):
        with tempfile.TemporaryDirectory() as directory:
            info = Path(directory) / "Info.plist"
            info.write_bytes(plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY))
            return subprocess.run([sys.executable, str(SCRIPT), str(info)], capture_output=True, text=True)

    def test_filename_includes_marketing_version_and_build_from_built_plist(self):
        result = self.run_fixture({"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Jarvis-EVO-0.1.0-build2-unsigned.ipa")

    def test_different_build_does_not_reuse_prior_candidate_name(self):
        result = self.run_fixture({"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "12"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Jarvis-EVO-0.1.0-build12-unsigned.ipa")

    def test_unsafe_or_non_numeric_version_is_rejected_without_filename(self):
        for key in ["CFBundleShortVersionString", "CFBundleVersion"]:
            for value in ["../2", "1/2", "2\n", "2;touch pwned", "", ".", "1..2", "２", 2]:
                with self.subTest(key=key, value=value):
                    metadata = {"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2", key: value}
                    result = self.run_fixture(metadata)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    self.assertIn(key, result.stderr)

    def test_missing_build_metadata_is_rejected(self):
        result = self.run_fixture({"CFBundleShortVersionString": "0.1.0"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("CFBundleVersion", result.stderr)


if __name__ == "__main__":
    unittest.main()
