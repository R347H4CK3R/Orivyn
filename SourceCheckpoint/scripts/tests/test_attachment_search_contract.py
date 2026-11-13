"""UI wiring contracts only, not execution of native Swift/Vision."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AttachmentSearchContract(unittest.TestCase):
 def test_preview_exposes_extracted_text_search_without_network(self):
  preview=(ROOT/'JarvisEVO/UI/AttachmentViews.swift').read_text()
  self.assertIn('AttachmentTextSearchView(text: text)',preview)
  self.assertIn('Search extracted text',preview)
 def test_search_is_explicit_and_discloses_limits(self):
  path=ROOT/'JarvisEVO/UI/AttachmentTextSearchView.swift'
  self.assertTrue(path.exists(), 'Offline extracted-text search UI has not been implemented')
  source=path.read_text()
  self.assertIn('AttachmentTextSearch.search(text: text, query: query)',source)
  self.assertIn('PDF page numbers',source)
  self.assertIn('wasTextTruncated',source)
  self.assertIn('moreMatches',source)
  self.assertNotIn('URLSession',source)
if __name__=='__main__':unittest.main()
