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
  self.assertIn('NavigationLink { HistoryImportView(model: model) }',s)
  view=s[s.index('private struct HistoryImportView: View {'):s.index('struct HistoryDocument: FileDocument')]
  self.assertIn('private var importPolicy: BackupImportPolicy = .preserveLocal',view)
  self.assertIn('Picker("Matching records", selection: $importPolicy)',view)
  self.assertIn('Text("Add missing only (keep local)").tag(BackupImportPolicy.preserveLocal)',view)
  self.assertIn('Text("Keep both versions (copy conflicts)").tag(BackupImportPolicy.keepBoth)',view)
  self.assertIn('Button("Choose backup file…")',view)
  self.assertIn('confirmation.beginSelection(policy: importPolicy)',view)
  self.assertIn('.disabled(model.isGenerating || importingHistory || confirmation.pending != nil)',view)
  self.assertIn('.fileImporter(isPresented: $importingHistory',view)
  self.assertIn('let policy = confirmation.finishSelection(selectionID)',view)
  self.assertIn('confirmation.select(url, policy: policy)',view)
  self.assertIn('Task { await model.importHistory(from: request.url, policy: request.policy) }',view)
 def test_replacement_has_explicit_inline_confirmation_and_balanced_access(self):
  s=(ROOT/'JarvisEVO/UI/SettingsView.swift').read_text()
  view=s[s.index('private struct HistoryImportView: View {'):s.index('struct HistoryDocument: FileDocument')]
  self.assertIn('if let pending = confirmation.pending',view)
  self.assertIn('Button("Replace matching records", role: .destructive)',view)
  self.assertIn('let request = confirmation.confirm()',view)
  self.assertIn('Button("Cancel replacement", role: .cancel) { cancelReplacement() }',view)
  self.assertIn('confirmation.invalidate()',view)
  self.assertIn('[selectionID = confirmation.selectionID] result in',view)
  self.assertLess(view.index('confirmation.finishSelection(selectionID)'),view.index('url.startAccessingSecurityScopedResource()'))
  self.assertIn('url.startAccessingSecurityScopedResource()',view)
  self.assertIn('defer { accessURL?.stopAccessingSecurityScopedResource() }',view)
  self.assertIn('replacementAccessURL?.stopAccessingSecurityScopedResource()',view)
  self.assertIn('An older backup can remove newer messages.',view)
  self.assertLess(view.index('let request = confirmation.confirm()'),view.index('await model.importHistory'))
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
