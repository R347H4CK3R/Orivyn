"""Native prompt wiring guard, not a claim of executed Swift selection."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class MemoryContextContract(unittest.TestCase):
 def test_generation_uses_bounded_selection_not_entire_library(self):
  s=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  self.assertNotIn('self.memories.map(\\.content).joined',s)
  self.assertIn('MemoryContextBuilder.build(',s)
  self.assertIn('maximumBytes: self.selectedProviderID == "remote" ? 1024 : 512',s)
  self.assertIn('lastMemoryContextSummary',s)
 def test_omissions_are_disclosed(self):
  s=(ROOT/'JarvisEVO/UI/SettingsView.swift').read_text()
  self.assertIn('A bounded selection',s)
  self.assertIn('lastMemoryContextSummary',s)
if __name__=='__main__':unittest.main()
