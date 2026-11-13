"""Source guards; native persistence execution is still required."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class BackupImportPolicyContract(unittest.TestCase):
 def test_preserve_local_filters_inside_transaction(self):
  s=(ROOT/'JarvisEVO/Persistence/SQLiteConversationStore.swift').read_text()
  method=s[s.index('func importData('):s.index('func memories(')]
  self.assertIn('policy: BackupImportPolicy = .replaceMatching',method)
  self.assertIn('policy == .preserveLocal',method)
  self.assertIn('incomingConversations.removeAll { conversationIDs.contains($0.id) }',method)
  self.assertIn('incomingMemories.removeAll { memoryIDs.contains($0.id) }',method)
  self.assertLess(method.index('BEGIN IMMEDIATE'),method.index('conversationIDs'))
  self.assertIn('for conversation in incomingConversations',method)
  self.assertIn('for note in incomingMemories',method)
 def test_ui_offers_non_destructive_transfer(self):
  s=(ROOT/'JarvisEVO/UI/SettingsView.swift').read_text()
  self.assertIn('Button("Add missing only (keep local)")',s)
  self.assertIn('importPolicy = .preserveLocal',s)
  self.assertIn('let policy = importPolicy',s)
  self.assertIn('policy: policy',s)
if __name__=='__main__':unittest.main()
