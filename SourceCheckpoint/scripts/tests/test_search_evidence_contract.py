"""Native tool wiring guards, not execution of Swift or SQLite."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class SearchEvidenceContract(unittest.TestCase):
 def test_tools_use_match_centered_evidence_and_escaped_output_budget(self):
  s=(ROOT/'JarvisEVO/Services/LocalReadTools.swift').read_text()
  self.assertIn('LocalConversationSearch.search(conversations: model.conversations, query: query, limit: Int(limit))',s)
  self.assertIn('LocalSearchExcerpt.excerpt(text: evidence.text, query: query)',(ROOT/'JarvisEVO/Core/LocalConversationSearch.swift').read_text())
  self.assertIn('LocalSearchExcerpt.excerpt(text: note.content, query: query)',s)
  self.assertIn('name == "search_conversations" ? 20_480',s)
if __name__=='__main__':unittest.main()
