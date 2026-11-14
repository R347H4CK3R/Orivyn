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
 def test_import_cancellation_checks_precede_commit_not_follow_it(self):
  s=(ROOT/'JarvisEVO/Persistence/SQLiteConversationStore.swift').read_text()
  method=s[s.index('private func importData('):s.index('private func textReceiveReceipt(')]
  self.assertIn('Task.checkCancellation()',method)
  self.assertLess(method.index('Task.checkCancellation()'),method.index('BEGIN IMMEDIATE'))
  self.assertIn('for conversation in incomingConversations { try Task.checkCancellation()',method)
  self.assertIn('for note in incomingMemories { try Task.checkCancellation()',method)
  # The first COMMIT belongs to the read-only receipt replay branch. It returns
  # an already durable outcome; the final COMMIT owns the new content writes.
  self.assertEqual(method.count('database.execute("COMMIT")'),2)
  write_commit=method.rindex('try database.execute("COMMIT")')
  self.assertTrue(method[:write_commit].rstrip().endswith('try Task.checkCancellation()'))
  self.assertNotIn('Task.checkCancellation()',method[write_commit:])
  self.assertIn('return summary',method[write_commit:])
 def test_receipt_replay_returns_durable_result_without_post_commit_cancellation(self):
  s=(ROOT/'JarvisEVO/Persistence/SQLiteConversationStore.swift').read_text()
  method=s[s.index('private func importData('):s.index('private func textReceiveReceipt(')]
  replay_start=method.index('if let prior = try textReceiveReceipt(data, identity: receive) {')
  replay_end=method.index('}',replay_start)
  replay=method[replay_start:replay_end]
  self.assertIn('try database.execute("COMMIT")',replay)
  commit=replay.index('try database.execute("COMMIT")')
  # The branch must return immediately: a cancellation after this commit must
  # not report a previously committed transfer as failed or fall into writes.
  self.assertEqual(replay[commit:].splitlines()[1].strip(),'return prior')
  self.assertNotIn('Task.checkCancellation()',replay[commit:])
if __name__=='__main__':unittest.main()
