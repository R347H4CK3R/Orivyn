"""Copy contract: persisted checkpoint results must not describe live CPU state.

Native resume behavior is covered by VirtualDesktopIntegrationUITests. These
portable assertions inspect the actual response strings, not a simulated VM.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CheckpointStatusCopyTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'JarvisEVO/Services/VirtualDesktop/VMHarness.swift').read_text()

    def response(self, name):
        match = re.search(r'case "' + name + r'": self\.checkpointStatus = "([^"]+)"', self.source)
        self.assertIsNotNone(match, 'Expected checkpoint response mapping')
        return match.group(1)

    def test_restore_result_remains_truthful_after_resume(self):
        self.assertEqual(self.response('restored'), 'Checkpoint verified and restored.')

    def test_saved_result_remains_truthful_after_resume(self):
        self.assertEqual(self.response('saved'), 'Checkpoint verified and saved.')

    def test_missing_checkpoint_is_not_reported_as_success(self):
        self.assertEqual(self.response('missing'), 'No compatible checkpoint saved.')

    def test_failure_and_live_runtime_guidance_are_preserved(self):
        self.assertIn('Checkpoint failed. Previous saved state is retained.', self.source)
        self.assertIn('Resume was not accepted. Check the current runtime state.', self.source)
        self.assertIn('Guest CPU paused. Resume explicitly; checkpoint result is shown separately.', self.source)
        self.assertIn('Guest CPU running. Desktop readiness has not been verified.', self.source)


if __name__ == '__main__':
    unittest.main()
