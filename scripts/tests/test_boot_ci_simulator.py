import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('boot_ci', Path(__file__).resolve().parents[1] / 'boot_ci_simulator.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
UUID = '12345678-1234-1234-1234-123456789ABC'
CI = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted'}


def inventory(available=True):
    return json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [
        {'udid': UUID, 'name': 'iPhone 16 Plus', 'isAvailable': available}]}})


class BootTests(unittest.TestCase):
    def invoke(self, outcomes, environment=CI, simulator=UUID):
        calls = []
        def run(arguments, **kwargs):
            calls.append((arguments, kwargs))
            self.assertGreater(kwargs['timeout'], 0)
            self.assertLessEqual(kwargs['timeout'], 120)
            result = outcomes.pop(0)
            if result == 'timeout':
                raise subprocess.TimeoutExpired(arguments, kwargs['timeout'], output=b'Waiting on BackBoard')
            return subprocess.CompletedProcess(arguments, result[0], result[1], '')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'simulator-boot.json'
            try:
                module.boot(simulator, path, environment=environment, run=run)
                error = None
            except Exception as caught:
                error = caught
            record = json.loads(path.read_text()) if path.exists() else None
        return calls, record, error

    def test_ready_boot_never_shuts_down(self):
        calls, record, error = self.invoke([(0, inventory()), (0, 'Ready')])
        self.assertIsNone(error); self.assertTrue(record['succeeded'])
        self.assertEqual(len(calls), 2)

    def test_hang_has_one_exact_targeted_recovery(self):
        calls, record, error = self.invoke([(0, inventory()), 'timeout', (0, inventory()), (0, ''), (0, 'Ready')])
        self.assertIsNone(error); self.assertTrue(record['succeeded'])
        self.assertEqual([call[0][2:] for call in calls], [
            ['list', 'devices', 'available', '-j'], ['bootstatus', UUID, '-b'],
            ['list', 'devices', 'available', '-j'], ['shutdown', UUID], ['bootstatus', UUID, '-b']])
        self.assertEqual(record['steps'][1]['stdout'], 'Waiting on BackBoard')

    def test_second_hang_fails_without_third_attempt(self):
        calls, record, error = self.invoke([(0, inventory()), 'timeout', (0, inventory()), (0, ''), 'timeout'])
        self.assertIsInstance(error, RuntimeError); self.assertFalse(record['succeeded'])
        self.assertEqual(len(calls), 5)

    def test_local_or_self_hosted_never_shutdown(self):
        for environment in [{}, {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'self-hosted'}]:
            calls, _, error = self.invoke([(0, inventory()), 'timeout'], environment=environment)
            self.assertIsInstance(error, RuntimeError); self.assertEqual(len(calls), 2)

    def test_revalidation_rejects_changed_device(self):
        calls, _, error = self.invoke([(0, inventory()), 'timeout', (0, inventory(False))])
        self.assertIsInstance(error, RuntimeError); self.assertEqual(len(calls), 3)

    def test_shutdown_error_or_timeout_stops(self):
        for result in [(1, ''), 'timeout']:
            calls, _, error = self.invoke([(0, inventory()), 'timeout', (0, inventory()), result])
            self.assertIsInstance(error, RuntimeError); self.assertEqual(len(calls), 4)

    def test_unsafe_alias_never_invokes_simctl(self):
        for simulator in ['booted', 'all', UUID + ';shutdown all']:
            calls, _, error = self.invoke([], simulator=simulator)
            self.assertIsInstance(error, ValueError); self.assertEqual(calls, [])

    def test_inventory_timeout_never_boots(self):
        calls, record, error = self.invoke(['timeout'])
        self.assertIsInstance(error, RuntimeError); self.assertEqual(len(calls), 1)
        self.assertFalse(record['succeeded'])
