"""Structural regression guards only; native behavior requires XCTest."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ConversationManagementContract(unittest.TestCase):
 def test_metadata_commits_before_visible_mutation(self):
  s=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  for name,next_name in [('rename','archive'),('archive','delete')]:
   method=s[s.index('    func '+name+'('):s.index('    func '+next_name+'(')]
   self.assertLess(method.index('try await store.save(proposed)'),method.index('conversations[index].'))
   self.assertIn('generatingConversationID != id',method)
 def test_edit_awaits_success_and_original_context_is_bound(self):
  view=(ROOT/'JarvisEVO/UI/MessageRow.swift').read_text()
  self.assertIn('let saved = await onSave(text)',view)
  self.assertIn('if saved { dismiss() }',view)
  root=(ROOT/'JarvisEVO/UI/RootView.swift').read_text()
  self.assertIn('sourceConversationID: editing.conversationID',root)
  self.assertIn('sourceConversationID: origin',root)
 def test_regeneration_rejects_user_target_and_keeps_composer(self):
  s=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  method=s[s.index('    func regenerate('):s.index('    func addAttachments(')]
  self.assertIn('original.messages[index].role == .assistant',method)
  self.assertNotIn('draft = ""',method)
  self.assertNotIn('clearPendingAttachments()',method)
 def test_new_chat_failure_does_not_close_history(self):
  model=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  self.assertIn('func newConversation() async -> Bool',model)
  history=(ROOT/'JarvisEVO/UI/HistoryView.swift').read_text()
  self.assertIn('if await model.newConversation()',history)
 def test_history_discloses_overlong_search(self):
  history=(ROOT/'JarvisEVO/UI/HistoryView.swift').read_text()
  self.assertIn('model.searchText.utf8.count > 1_024',history)
  self.assertIn('Search is limited to 1,024 UTF-8 bytes',history)
if __name__=='__main__':unittest.main()
