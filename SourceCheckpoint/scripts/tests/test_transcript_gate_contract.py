import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class TranscriptGateContractTests(unittest.TestCase):
    def test_native_gate_selects_transcript_suite(self):
        self.assertIn('-only-testing:JarvisEVOTests/ConversationTranscriptTests', (ROOT/'scripts/run_virtual_desktop_gate.sh').read_text())
