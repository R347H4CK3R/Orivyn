from pathlib import Path
import os
import subprocess
import tempfile
import unittest
import zipfile

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



class SimulatorPhotoSeedTests(unittest.TestCase):
    simulator = "11111111-2222-3333-4444-555555555555"

    def run_seed(self, *, state="Booted", destination=None, seed_status=0, native_status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts = root / "artifacts"
            artifacts.mkdir()
            events = root / "events"
            runner = root / "xcodebuild"
            runner.write_text("#!/bin/bash\nprintf 'native\n' >> \"$EVENTS\"\n" + f"exit {native_status}\n")
            runner.chmod(0o755)
            fake = root / "xcrun"
            devices = '{"devices":{"iOS-26":[{"udid":"' + self.simulator + '","state":"' + state + '","isAvailable":true}]}}'
            fake.write_text("#!/bin/bash\n" +
                "if [[ \"$1 $2\" == 'simctl list' ]]; then printf '%s\n' '" + devices + "'; exit 0; fi\n" +
                "if [[ \"$1 $2\" == 'simctl addmedia' ]]; then printf 'seed:%s:%s\n' \"$3\" \"$4\" >> \"$EVENTS\"; exit " + str(seed_status) + "; fi\nexit 0\n")
            fake.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"], EVENTS=str(events))
            args = ["bash", str(SCRIPT), str(artifacts), "xcodebuild", "-destination",
                    destination or f"platform=iOS Simulator,id={self.simulator}", "test"]
            result = subprocess.run(args, env=env, text=True, capture_output=True)
            return result, events.read_text().splitlines() if events.exists() else []

    def test_exact_booted_simulator_is_seeded_before_native_tests(self):
        result, events = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(events), 2)
        self.assertTrue(events[0].startswith(f"seed:{self.simulator}:"))
        self.assertTrue(events[0].endswith("/UITests/Fixtures/OCR-card.png"))
        self.assertEqual(events[1], "native")

    def test_unbooted_destination_blocks_seed_and_tests(self):
        result, events = self.run_seed(state="Shutdown")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, [])

    def test_generic_destination_never_seeds_an_arbitrary_booted_simulator(self):
        result, events = self.run_seed(destination="platform=iOS Simulator,name=iPhone 16 Plus")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, [])

    def test_seed_failure_blocks_native_success(self):
        result, events = self.run_seed(seed_status=17)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(len(events), 1)

    def test_seeding_does_not_mask_later_native_failure(self):
        result, events = self.run_seed(native_status=65)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(events[-1], "native")


class EvidenceBundleTests(unittest.TestCase):
    def collect(self, root):
        return subprocess.run(["bash", str(SCRIPT), "--bundle-evidence", str(root)], capture_output=True, text=True)

    def archive_contents(self, run):
        result = {}
        for archive in sorted(run.glob("*-evidence-*.zip")):
            with zipfile.ZipFile(archive) as zipped:
                for name in zipped.namelist():
                    self.assertNotIn(name, result)
                    result[name] = zipped.read(name)
        return result

    def test_small_bundles_keep_logs_images_manifest_and_original_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / "run-one"
            screens = run / "screenshots" / "nested"
            screens.mkdir(parents=True)
            files = {"native-tests.log": b"native failed", "device-build.log": b"device output",
                     "ipa-verification.json": b'{"verified":true}', "xcode-version.txt": b"Xcode 26",
                     "SHA256SUMS": b"abc candidate.ipa", "screenshots/nested/main.png": b"PNG bytes",
                     "screenshots/nested/dark.jpeg": b"JPEG bytes", "screenshots/manifest.json": b"[]",
                     "screenshots/hierarchy.txt": b"real UI hierarchy"}
            for name, data in files.items():
                target = run / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            result_data = run / "Tests.xcresult" / "Data"
            result_data.mkdir(parents=True)
            (result_data / "large-data").write_bytes(b"preserve full result")
            (run / "screenshots" / "recording.mp4").write_bytes(b"large recording")
            (run / "candidate.ipa").write_bytes(b"separate IPA")
            result = self.collect(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.archive_contents(run), files)
            self.assertEqual((result_data / "large-data").read_bytes(), b"preserve full result")
            self.assertEqual((run / "candidate.ipa").read_bytes(), b"separate IPA")

    def test_large_screenshot_group_is_split_without_truncating_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / "run-one"
            screens = run / "screenshots"
            screens.mkdir(parents=True)
            first, second = b"a" * (5 * 1024 * 1024), b"b" * (5 * 1024 * 1024)
            (screens / "first.png").write_bytes(first)
            (screens / "second.jpg").write_bytes(second)
            result = self.collect(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(list(run.glob("screenshots-evidence-*.zip"))), 2)
            self.assertEqual(self.archive_contents(run), {"screenshots/first.png": first, "screenshots/second.jpg": second})

    def test_symlinked_files_are_not_included_as_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "artifacts"
            run = root / "run-one"
            screens = run / "screenshots"
            screens.mkdir(parents=True)
            outside = root.parent / "outside.txt"
            outside.write_bytes(b"must not be copied")
            (run / "native-tests.log").write_bytes(b"safe log")
            (run / "linked.log").symlink_to(outside)
            (screens / "linked.png").symlink_to(outside)
            result = self.collect(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.archive_contents(run), {"native-tests.log": b"safe log"})

    def test_symlinked_output_archive_cannot_overwrite_external_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "artifacts"
            run = root / "run-one"
            run.mkdir(parents=True)
            (run / "native-tests.log").write_bytes(b"safe log")
            outside = root.parent / "outside.txt"
            outside.write_bytes(b"keep outside")
            (run / "logs-evidence-001.zip").symlink_to(outside)
            result = self.collect(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(outside.read_bytes(), b"keep outside")

    def run_build(self, status, *, invalid_artifacts=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts = root / "artifacts with spaces"
            if invalid_artifacts:
                artifacts.write_text("not a directory")
            command = root / "build-command"
            command.write_text("#!/bin/bash\n" +
                               ("" if invalid_artifacts else 'mkdir -p "$1/run-one"\nprintf "build log\\n" > "$1/run-one/native-tests.log"\n') +
                               f"exit {status}\n")
            command.chmod(0o755)
            result = subprocess.run(["bash", str(SCRIPT), "--run-build", str(artifacts), "bash", str(command), str(artifacts)],
                                    capture_output=True, text=True)
            archives = list(artifacts.glob("*/*-evidence-*.zip")) if artifacts.is_dir() else []
            return result, len(archives)

    def test_failed_build_still_bundles_evidence_and_preserves_original_exit(self):
        result, count = self.run_build(65)
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertEqual(count, 1)

    def test_evidence_failure_cannot_mask_original_build_failure(self):
        result, _ = self.run_build(65, invalid_artifacts=True)
        self.assertEqual(result.returncode, 65, result.stderr)

    def test_evidence_failure_blocks_otherwise_passing_build(self):
        result, _ = self.run_build(0, invalid_artifacts=True)
        self.assertNotEqual(result.returncode, 0)

    def test_successful_build_bundles_evidence_and_remains_successful(self):
        result, count = self.run_build(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count, 1)


if __name__ == "__main__":
    unittest.main()
