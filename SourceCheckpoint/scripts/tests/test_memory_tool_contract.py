"""Native memory tool wiring guards; runtime behavior requires native tests."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class MemoryToolContract(unittest.TestCase):
 def test_native_memory_read_is_bounded_and_explicit(self):
  s=(ROOT/'JarvisEVO/Services/LocalReadTools.swift').read_text()
  self.assertIn('case "search_memory":',s)
  self.assertIn('model.memories.prefix(500)',s)
  self.assertIn('"searchedMemories"',s)
  ui=(ROOT/'JarvisEVO/UI/VerifiedLocalReadView.swift').read_text()
  self.assertIn('Toggle("Search saved memory"',ui)
  self.assertIn('memoryQuery: memoryEnabled ? memoryQuery : nil',ui)
  core=(ROOT/'JarvisEVO/Services/VerifiedLocalPlanCore.swift').read_text()
  self.assertIn('let memoryQuery: String?',core)
  self.assertIn('name == "search_memory" ? 16_384 : 4096',s)
if __name__=='__main__':unittest.main()
