"""Source assertions, not native execution or clipboard reads."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class WebExtras(unittest.TestCase):
 def test_reader_bound_to_immutable_presentation(self):
  core=(ROOT/'JarvisEVO/Core/NativeToolDrafts.swift').read_text()
  self.assertIn('struct BrowserPresentation',core)
  self.assertIn('reader: Bool = false',core)
  self.assertIn('guard !reader || draft.isWebsite',core)
  view=(ROOT/'JarvisEVO/UI/BrowserToolView.swift').read_text()
  self.assertIn('configuration.entersReaderIfAvailable = prefersReader',view)
  self.assertIn('prefersReader: opened.prefersReader',view)
 def test_copy_only_explicit_local_write_with_preview(self):
  view=(ROOT/'JarvisEVO/UI/BrowserToolView.swift').read_text()
  self.assertIn('Button("Copy Clean Link"',view)
  self.assertIn('Text(cleanLink)',view)
  self.assertEqual(view.count('UIPasteboard.general'),1)
  self.assertIn('.localOnly: true',view)
  self.assertNotIn('UIPasteboard.general.string',view)
  self.assertNotIn('URLSession',view)
 def test_clean_link_has_separate_raw_query_filter(self):
  core=(ROOT/'JarvisEVO/Core/NativeToolDrafts.swift').read_text()
  self.assertIn('enum WebCleanLink',core)
  self.assertIn('omittingEmptySubsequences: false',core)
  self.assertIn('if kept.count == fields.count { return original }',core)
  view=(ROOT/'JarvisEVO/UI/BrowserToolView.swift').read_text()
  self.assertIn('WebCleanLink.validated(address)',view)
if __name__=='__main__': unittest.main()
