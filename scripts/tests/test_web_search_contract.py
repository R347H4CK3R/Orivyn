"""Source-only invariants; not native UI execution."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class WebContract(unittest.TestCase):
 def test_fixed_encoded_destination(self):
  s=(ROOT/'JarvisEVO/Core/NativeToolDrafts.swift').read_text()
  self.assertIn('enum WebSearchDestination',s)
  self.assertIn('URLQueryItem(name: "q", value: query)',s)
  self.assertIn('parts.host = "duckduckgo.com"',s)
  self.assertIn('BrowserDestination.validated(url.absoluteString)',s)
 def test_view_requires_explicit_activation_without_chat_context(self):
  s=(ROOT/'JarvisEVO/UI/BrowserToolView.swift').read_text()
  for required in ['browser.open', 'WebNavigationDraft.validated(address)', 'Save bookmark', 'scenePhase == .active', 'SFSafariViewController']:
   self.assertIn(required,s)
  for forbidden in ['URLSession', 'AppModel', 'model.draft', 'activeConversation', '.onSubmit', '.task {', '.onChange(of: searchTerms']:
   self.assertNotIn(forbidden,s)
 def test_root_visible_web_only_opens_review(self):
  s=(ROOT/'JarvisEVO/UI/RootView.swift').read_text()
  self.assertIn('Button("Web", systemImage: "globe")',s)
  self.assertIn('accessibilityIdentifier("chat.web")',s)
 def test_bookmark_save_is_explicit_and_strips_sensitive_components(self):
  s=(ROOT/'JarvisEVO/Core/NativeToolDrafts.swift').read_text()
  for token in ['final class WebBookmarkStore', 'parts.query = nil', 'parts.fragment = nil', 'func saveWebsite']:
   self.assertIn(token,s)
 def test_trim_precedes_classification_and_bookmark_buttons_are_independent(self):
  s=(ROOT/'JarvisEVO/Core/NativeToolDrafts.swift').read_text().split('struct WebNavigationDraft {')[1].split('@MainActor')[0]
  self.assertLess(s.index('let input = text.trimmingCharacters'),s.index('input.range(of:'))
  self.assertIn('BrowserDestination.validated(input)',s)
  view=(ROOT/'JarvisEVO/UI/BrowserToolView.swift').read_text()
  self.assertGreaterEqual(view.count('.buttonStyle(.borderless)'),2)
  self.assertIn('browser.bookmark.fill.',view)
  self.assertIn('browser.bookmark.remove.',view)
if __name__=='__main__': unittest.main()
