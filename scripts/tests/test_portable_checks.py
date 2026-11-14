"""Failure/evidence behavior of the local verification entry point."""
import contextlib
import io
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('portable_checks', ROOT / 'scripts/run_portable_checks.py')
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class PortableChecksTests(unittest.TestCase):
    def test_guest_is_prepared_before_contract_checks_and_failure_is_retained(self):
        for preparation_status in ['passed', 'failed']:
            with self.subTest(preparation_status=preparation_status), tempfile.TemporaryDirectory() as folder:
                out = Path(folder) / 'evidence'
                calls = []

                def stage(name, command, root, output, **kwargs):
                    calls.append((name, command))
                    return {'name': name, 'status': preparation_status if name == 'guest' else 'passed'}

                with mock.patch.object(checks, 'run_stage', side_effect=stage), \
                     mock.patch.object(checks, 'source_manifest', return_value=[]), \
                     contextlib.redirect_stdout(io.StringIO()):
                    result = checks.main(['--swift', 'unused', '--output', str(out)])
                self.assertEqual(calls[0], ('guest', [sys.executable, '-B', 'scripts/materialize_guest.py',
                    'Fixtures/maintained.img.gz', 'JarvisEVO/Resources/VMAssets/maintained.img']))
                self.assertIn('python', [name for name, _ in calls])
                summary = json.loads((out / 'SUMMARY.json').read_text())
                self.assertEqual(next(s for s in summary['stages'] if s['name'] == 'guest')['status'], preparation_status)
                self.assertEqual(result, 1 if preparation_status == 'failed' else 0)

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

    def test_timeout_preserves_partial_log_and_reports_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            result = checks.run_stage('timeout', [sys.executable, '-u', '-c', 'import time; print("before timeout"); time.sleep(30)'], ROOT, out, timeout_seconds=0.2)
            self.assertEqual(result['status'], 'failed')
            self.assertTrue(result['timed_out'])
            self.assertIsNone(result['exit_code'])
            self.assertIn('before timeout', (out / result['log']).read_text())
            self.assertIn('timed out', (out / result['log']).read_text())
            json.dumps(result)
            following = checks.run_stage('following', [sys.executable, '-c', 'print("still runs")'], ROOT, out, timeout_seconds=1)
            self.assertEqual(following['status'], 'passed')

    def test_nonpositive_timeout_rejected_before_creating_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / 'evidence'
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                checks.main(['--swift', 'unused', '--output', str(out), '--stage-timeout', '0'])
            self.assertFalse(out.exists())
