"""Structural gates only, not Swift/native runtime evidence."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class AutoContract(unittest.TestCase):
 def test_provider_selects_after_fresh_catalog(self):
  s=(ROOT/'JarvisEVO/Providers/OpenRouterFreeProvider.swift').read_text()
  self.assertIn('enum FreeOnlineAutoRouter',s)
  self.assertIn('String(text.prefix(4096))',s)
  self.assertIn('FreeOnlineAutoRouter.select(text: newlyAuthoredText, verifiedModels: models)',s)
  self.assertLess(s.index('let models = try await fetchCatalog()'),s.index('FreeOnlineAutoRouter.select(text: newlyAuthoredText'))
  self.assertEqual(s.count('request.httpMethod = "POST"'),1)
 def test_consent_is_not_model_selection(self):
  s=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text().split('final class FreeOnlineChatState {')[1]
  self.assertIn('private(set) var hasConsented = false',s)
  self.assertIn('private(set) var usesAutomaticSelection = true',s)
  self.assertNotIn('var hasConsented: Bool { selectedModelID != nil }',s)
  self.assertIn('completeAutomatically(text, key)',s)
 def test_ui_auto_before_manual_and_actual_model(self):
  s=(ROOT/'JarvisEVO/UI/FreeOnlineChatView.swift').read_text()
  self.assertLess(s.index('freeOnline.auto'),s.index('ForEach(matches)'))
  self.assertIn('state.useFreeOnlineAuto()',s)
  self.assertIn('state.lastResponseModelName',s)
if __name__=='__main__': unittest.main()
