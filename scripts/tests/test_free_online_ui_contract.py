"""Source isolation checks only. Native UI execution remains a separate gate."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class OnlineUIContract(unittest.TestCase):
 def test_dedicated_view_has_no_offline_model_or_automatic_network(self):
  p=ROOT/'JarvisEVO/UI/FreeOnlineChatView.swift'
  self.assertTrue(p.exists(), 'Dedicated online view is missing')
  s=p.read_text()
  for token in ['@Bindable var state: FreeOnlineChatState','FreeOnlineChatState.disclosure','state.useFreeOnline','SecureField','state.returnToOffline()','state.refreshCatalog()','No paid fallback','state.send()']:
   self.assertIn(token,s)
  for token in ['AppModel', 'model.draft', 'activeConversation', 'pendingAttachments', '.task {', 'Keychain', 'UserDefaults']:
   self.assertNotIn(token,s)
 def test_confirmation_captures_choice_and_background_resets_preview(self):
  s=(ROOT/'JarvisEVO/UI/FreeOnlineChatView.swift').read_text()
  self.assertIn('presenting: proposedModel',s)
  self.assertIn('useFreeOnline(modelID: choice.id)',s)
  self.assertIn('didRefresh = false; state.returnToOffline()',s)
 def test_online_entry_does_not_replace_legacy_connection(self):
  s=(ROOT/'JarvisEVO/UI/ModelManagerView.swift').read_text()
  self.assertIn('freeOnline.open',s)
  self.assertIn('Not part of the free catalog',s)
if __name__=='__main__': unittest.main()
