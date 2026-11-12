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

class DelegateContracts(unittest.TestCase):
 def test_native_policy_delegates_match_ios26_sendable_signatures(self):
  source=(ROOT/'Diagnostics/VMProof/Sources/VMHarness.swift').read_text()
  self.assertIn('@escaping @MainActor @Sendable (WKNavigationActionPolicy)',source)
  self.assertIn('@escaping @MainActor @Sendable (WKNavigationResponsePolicy)',source)

class FreeBuildBudget(unittest.TestCase):
 def test_bios_gate_reserves_twenty_of_remaining_twenty_nine_minutes(self):
  workflow=(ROOT/'codemagic.yaml').read_text().split('  orivyn-bios-compatibility:',1)[1]
  self.assertIn('max_build_duration: 9',workflow)
