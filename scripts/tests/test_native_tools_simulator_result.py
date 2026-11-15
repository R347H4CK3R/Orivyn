import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[2] / 'Diagnostics/NativeTools/verify_simulator_result.py'
spec = importlib.util.spec_from_file_location('native_tools_result', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NativeToolsSimulatorResultTests(unittest.TestCase):
    def test_exact_success(self):
        module.verify(dict(totalTestCount=1, passedTests=1, failedTests=0, skippedTests=0))

    def test_skip_cannot_pass(self):
        with self.assertRaises(ValueError):
            module.verify(dict(totalTestCount=1, passedTests=0, failedTests=0, skippedTests=1))

    def test_missing_zero_extra_failed_or_wrong_types_cannot_pass(self):
        baseline = dict(totalTestCount=1, passedTests=1, failedTests=0, skippedTests=0)
        for change in [dict(totalTestCount=0), dict(totalTestCount=2), dict(failedTests=1), dict(passedTests=True), dict(skippedTests='0')]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                module.verify(baseline | change)
        with self.assertRaises(ValueError):
            module.verify({})
