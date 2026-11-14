"""Source wiring checks, not native llama/Swift execution."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class LocalCompletionContract(unittest.TestCase):
 def test_success_requires_observed_end_token(self):
  source=(ROOT/'JarvisEVO/Providers/Local/LlamaEngine.swift').read_text()
  self.assertIn('var sawEndOfGeneration = false', source)
  self.assertIn('if llama_vocab_is_eog(vocabulary, token) { sawEndOfGeneration = true; break }', source)
  self.assertIn('guard sawEndOfGeneration else { throw LocalModelError.generationLimitReached }',source)
 def test_omitted_attachment_count_is_explicit(self):
  source=(ROOT/'JarvisEVO/Providers/Local/LocalPromptBuilder.swift').read_text()
  self.assertIn('omittedAttachments += 1',source)
  self.assertIn('additional attachment(s) omitted',source)
if __name__=='__main__':unittest.main()
