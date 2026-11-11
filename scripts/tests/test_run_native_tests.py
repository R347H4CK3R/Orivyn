from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "run_native_tests.sh"


class NativeEvidenceRunnerTests(unittest.TestCase):
    def run_fixture(self, test_status, *, export_status=0, create_bundle=True, block_log=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts = root / "artifacts with spaces"
            artifacts.mkdir()
            if block_log:
                (artifacts / "native-tests.log").mkdir()
            command = root / "native-command"
            command.write_text("#!/bin/bash\nprintf 'native stdout\\n'\nprintf 'native stderr\\n' >&2\n" +
                               ('mkdir -p "$ARTIFACTS/Tests.xcresult"\n' if create_bundle else "") +
                               f"exit {test_status}\n")
            command.chmod(0o755)
            exporter = root / "xcrun"
            exporter.write_text("#!/bin/bash\nprintf '%s\\n' \"$@\" > \"$ARTIFACTS/export-arguments.txt\"\n" + f"exit {export_status}\n")
            exporter.chmod(0o755)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"], ARTIFACTS=str(artifacts))
            result = subprocess.run(["bash", str(SCRIPT), str(artifacts), str(command)], env=environment, capture_output=True, text=True)
            log = artifacts / "native-tests.log"
            arguments = artifacts / "export-arguments.txt"
            return result, (log.read_text() if log.is_file() else None), (arguments.read_text().splitlines() if arguments.exists() else None)

    def test_success_keeps_combined_log_and_exports_result_attachments(self):
        result, log, arguments = self.run_fixture(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("native stdout", log)
        self.assertIn("native stderr", log)
        self.assertEqual(arguments[:3], ["xcresulttool", "export", "attachments"])
        self.assertEqual(arguments[3], "--path")
        self.assertTrue(arguments[4].endswith("/Tests.xcresult"))
        self.assertEqual(arguments[5], "--output-path")
        self.assertTrue(arguments[6].endswith("/screenshots"))

    def test_failed_native_tests_still_export_and_remain_failed(self):
        result, log, arguments = self.run_fixture(65)
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertIn("native stderr", log)
        self.assertIsNotNone(arguments)

    def test_failed_attachment_export_cannot_mask_native_failure(self):
        result, _, arguments = self.run_fixture(65, export_status=1)
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertIsNotNone(arguments)

    def test_missing_result_bundle_preserves_failure_without_export(self):
        result, log, arguments = self.run_fixture(65, create_bundle=False)
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertIn("native stdout", log)
        self.assertIsNone(arguments)

    def test_failed_log_write_blocks_passing_gate(self):
        result, _, _ = self.run_fixture(0, block_log=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("native-tests.log", result.stderr)


if __name__ == "__main__":
    unittest.main()
