"""Source contracts only; actual Swift persistence/UI tests still require native gate."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class MemoryEditorContract(unittest.TestCase):
 def test_editor_waits_for_save_keeps_text_and_stable_identity(self):
  source=(ROOT/'JarvisEVO/UI/SettingsView.swift').read_text()
  self.assertIn('let saved = await save(content)',source)
  self.assertIn('if saved { dismiss() }',source)
  self.assertIn('Your text is kept here',source)
  self.assertIn('TextEditor(text: $content).disabled(saving)',source)
  self.assertIn('memoryID = id ?? UUID()',source)
 def test_model_returns_real_outcome_and_enforces_bound(self):
  source=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  method=source[source.index('    func saveMemory('):source.index('    func deleteMemory(')]
  self.assertIn('async -> Bool',method)
  self.assertIn('content.count <= 4_000',method)
  self.assertLess(method.index('try await store.saveMemory'),method.index('return true'))
  self.assertIn('return false',method)
if __name__=='__main__':unittest.main()
