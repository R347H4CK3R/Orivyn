"""Static wiring guard only; token fitting behavior needs native tests."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AttachmentFittingContract(unittest.TestCase):
 def test_engine_uses_tokenizer_aware_preparation(self):
  s=(ROOT/'JarvisEVO/Providers/Local/LlamaEngine.swift').read_text()
  self.assertIn('LocalPromptBuilder.prepareMessages(from: request.messages',s)
  self.assertIn('let rendered = try format(entries, systemPrompt: request.systemPrompt',s)
 def test_composer_explains_excerpt_scope(self):
  s=(ROOT/'JarvisEVO/UI/RootView.swift').read_text()
  self.assertIn('Models may receive shortened text excerpts',s)
  self.assertIn('Open an attachment to search its stored extracted text',s)
if __name__=='__main__':unittest.main()
