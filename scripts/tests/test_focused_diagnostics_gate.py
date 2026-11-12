from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class FocusedDiagnostics(unittest.TestCase):
 def test_independent_native_statuses_and_no_release(self):
  script=(ROOT/'scripts/run_focused_diagnostics.sh').read_text()
  self.assertIn('BIOS_STATUS=${PIPESTATUS[0]}',script)
  self.assertIn('KNOWLEDGE_STATUS=${PIPESTATUS[0]}',script)
  self.assertIn('run_self_knowledge_gate.sh',script)
  self.assertIn('BIOS_STATUS == 0 && KNOWLEDGE_STATUS == 0',script)
  self.assertNotIn('run_build.sh',script)
  self.assertNotIn('build_ipa',script)
