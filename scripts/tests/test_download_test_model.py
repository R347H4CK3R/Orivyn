import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("download_test_model", Path(__file__).resolve().parents[1] / "download_test_model.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

# Standard SHA-256 test vector for ASCII "abc", independent of verifier code.
ABC_SHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

class ModelIntegrityTests(unittest.TestCase):
    def verify_fixture(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.gguf"
            path.write_bytes(data)
            with patch.object(MODULE, "SIZE", 3), patch.object(MODULE, "SHA256", ABC_SHA256):
                MODULE.verify(path)

    def test_verified_content_is_accepted(self):
        self.verify_fixture(b"abc")

    def test_truncated_content_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            self.verify_fixture(b"ab")

    def test_same_size_modified_content_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            self.verify_fixture(b"abd")

if __name__ == "__main__":
    unittest.main()
