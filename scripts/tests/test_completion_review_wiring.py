import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class CompletionReviewWiring(unittest.TestCase):
 def test_prepare_has_no_model_or_tool_work_and_approve_checks_exact_binding(self):
  s=(ROOT/'JarvisEVO/Services/LocalAgentSession.swift').read_text()
  prepare=s.split('func prepareCompletion(',1)[1].split('func approveCompletion(',1)[0]
  for forbidden in ['.stream(', 'Task {', 'executeLocalTool(', 'createContract']:
   self.assertNotIn(forbidden,prepare)
  approve=s.split('func approveCompletion(',1)[1].split('func create(',1)[0]
  self.assertLess(approve.index('review.matches('),approve.index('"createContract"'))
  self.assertIn('selected.model.sha256',approve)
 def test_run_never_starts_while_scope_review_pending(self):
  s=(ROOT/'JarvisEVO/Services/LocalAgentSession.swift').read_text().split('func run() {',1)[1]
  self.assertIn('proposedCompletion == nil',s.split('let identity',1)[0])
 def test_review_ui_has_separate_approve_and_no_auto_run(self):
  s=(ROOT/'JarvisEVO/UI/LocalAgentView.swift').read_text()
  self.assertIn('completion.review',s);self.assertIn('completion.approve',s);self.assertIn('completion.discard',s)
  self.assertIn('session?.discardReadPlan()',s)
  self.assertNotIn('}.accessibilityIdentifier("completion.review")',s)
