"""Failure/evidence behavior of the local verification entry point."""
import contextlib
import io
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('portable_checks', ROOT / 'scripts/run_portable_checks.py')
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class PortableChecksTests(unittest.TestCase):
    def test_failing_process_preserves_output_and_exit_code(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            result = checks.run_stage('failure', [sys.executable, '-c', 'print("regression evidence"); raise SystemExit(7)'], ROOT, out)
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['exit_code'], 7)
            self.assertIn('regression evidence', (out / result['log']).read_text())
            json.dumps(result)

    def test_missing_executable_is_failure_not_skip(self):
        with tempfile.TemporaryDirectory() as folder:
            result = checks.run_stage('missing', [str(Path(folder) / 'absent')], ROOT, Path(folder))
            self.assertEqual(result['status'], 'failed')
            self.assertIsNone(result['exit_code'])
            self.assertTrue((Path(folder) / result['log']).read_text())

    def test_success_keeps_stderr_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            result = checks.run_stage('ok', [sys.executable, '-c', 'import sys; print("diagnostic", file=sys.stderr)'], ROOT, Path(folder))
            self.assertEqual(result['status'], 'passed')
            self.assertIn('diagnostic', (Path(folder) / result['log']).read_text())

    def test_existing_evidence_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            marker = Path(folder) / 'SUMMARY.json'
            marker.write_text('existing evidence')
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as failure:
                checks.main(['--swift', 'unused', '--output', folder])
            self.assertNotEqual(failure.exception.code, 0)
            self.assertEqual(marker.read_text(), 'existing evidence')
