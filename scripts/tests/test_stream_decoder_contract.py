"""Source guard; native Unicode behavior tests require Swift."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class StreamDecoderContract(unittest.TestCase):
 def test_decoder_does_not_block_all_text_on_invalid_prefix(self):
  s=(ROOT/'JarvisEVO/Providers/Local/UTF8TokenAccumulator.swift').read_text()
  self.assertNotIn('guard let value = String(bytes: pending, encoding: .utf8) else { return nil }',s)
  self.assertIn('pendingByteCount',s)
 def test_native_gate_includes_decoder_behavior(self):
  s=(ROOT/'scripts/run_virtual_desktop_gate.sh').read_text()
  self.assertIn('-only-testing:JarvisEVOTests/UTF8TokenAccumulatorTests',s)
if __name__=='__main__':unittest.main()
