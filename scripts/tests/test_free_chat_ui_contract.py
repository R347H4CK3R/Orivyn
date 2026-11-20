"""Portable source contracts only; XCTest/native rendering are separate gates."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class FreeChatUIContract(unittest.TestCase):
 def test_home_keeps_existing_actions_and_adds_clear_picker(self):
  s=(ROOT/'JarvisEVO/UI/RootView.swift').read_text()
  for token in ['Choose an AI','welcome.chooseAI','suggestion.plan','suggestion.write','suggestion.explain','composer.input','composer.send','composer.voice','history.open']:
   self.assertIn(token,s)
  self.assertIn('FreeChatStyle.navy',s)
 def test_picker_keeps_variants_and_separates_legacy_online(self):
  s=(ROOT/'JarvisEVO/UI/ModelManagerView.swift').read_text()
  for token in ['Works offline','Needs internet','More download options','model.catalog.search','model.download.cancel','model.provider.','Not part of the free catalog','catalogGroups']:
   self.assertIn(token,s)
 def test_quick_prompts_do_not_send(self):
  s=(ROOT/'JarvisEVO/UI/RootView.swift').read_text().split('private func suggestion(')[1].split('private var transcript')[0]
  self.assertIn('model.draft = prompt',s)
  self.assertNotIn('model.send()',s)
if __name__=='__main__': unittest.main()
