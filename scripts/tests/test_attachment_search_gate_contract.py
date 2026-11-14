import pathlib
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class AttachmentSearchGateContractTests(unittest.TestCase):
 def test_native_gate_selects_attachment_search(self):
  self.assertIn('-only-testing:JarvisEVOTests/LocalConversationSearchTests',(ROOT/'scripts/run_virtual_desktop_gate.sh').read_text())
