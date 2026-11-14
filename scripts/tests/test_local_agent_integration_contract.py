"""Structural integration contracts; not Swift or native execution evidence."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class LocalAgentContract(unittest.TestCase):
 def test_only_bundled_javascript_is_evaluated(self):
  p=ROOT/'JarvisEVO/Services/LocalAgentCore.swift'
  self.assertTrue(p.exists(),'Native local-agent core missing')
  s=p.read_text();self.assertEqual(s.count('evaluateScript('),1)
  self.assertIn('call(withArguments: arguments)',s)
 def test_task_runs_local_provider_and_persists_before_tool(self):
  p=ROOT/'JarvisEVO/Services/LocalAgentSession.swift'
  self.assertTrue(p.exists(),'Native local-agent session missing')
  s=p.read_text();self.assertIn('selectedLocalAgentProvider',s)
  self.assertLess(s.index('try persist(next)'),s.index('try executeLocalTool('))
  self.assertIn('await model.finishLocalAgentWork(id:',s)
 def test_internal_agent_uses_shared_json_request_without_changing_chat_preference(self):
  session=(ROOT/'JarvisEVO/Services/LocalAgentSession.swift').read_text()
  self.assertIn('GenerationRequest.localAgent(prompt: prompt,',session)
  self.assertIn('requiresTool: !item.history.contains { $0.outcome == "succeeded" }',session)
  self.assertNotIn('let request = GenerationRequest(messages:',session)
  chat=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  self.assertIn('conciseQwen3: self.conciseQwen3',chat)
 def test_grammar_is_explicit_resource_and_agent_tests_are_gated(self):
  project=(ROOT/'project.yml').read_text()
  self.assertIn('- path: JarvisEVO/Resources/LocalAgentDecision.gbnf\n        buildPhase: resources',project)
  for name in ['ci_macos.sh','run_virtual_desktop_gate.sh']:
   self.assertIn('node --test scripts/agent-tests/*.test.cjs',(ROOT/'scripts'/name).read_text())
  self.assertIn('-only-testing:JarvisEVOTests/LocalAgentCoreTests',(ROOT/'scripts/run_virtual_desktop_gate.sh').read_text())
 def test_arithmetic_evidence_is_separate_from_model_answer(self):
  source=(ROOT/'JarvisEVO/Core/LocalAgentSnapshot.swift').read_text()
  event=source[source.index('struct Event:'):source.index('let history:')]
  self.assertIn('let arguments: MCPJSONValue',event)
  ui=(ROOT/'JarvisEVO/UI/LocalAgentView.swift').read_text()
  self.assertIn('event.calculationEvidence(goal: task.goal)',ui)
  self.assertIn('Recomputed arithmetic',ui)
  self.assertIn('Model answer · not verified',ui)
 def test_verified_mode_does_not_invoke_inference_and_persists_before_read(self):
  s=(ROOT/'JarvisEVO/Services/VerifiedLocalReadSession.swift').read_text()
  self.assertNotIn('GenerationRequest',s)
  self.assertNotIn('provider.stream',s)
  self.assertLess(s.index('try persist(next)'),s.index('try LocalReadTools.execute('))
  self.assertIn('model.beginVerifiedReads',s)
  self.assertIn('model.endVerifiedReads',s)
 def test_reload_does_not_recover_another_sessions_live_work(self):
  for filename, method, guard in [
   ('LocalAgentSession.swift','    func reloadRecords() throws {','canManageSavedTasks'),
   ('VerifiedLocalReadSession.swift','    func reload() throws {','canManage')]:
   source=(ROOT/'JarvisEVO/Services'/filename).read_text()
   body=source[source.index(method):]
   self.assertIn('guard '+guard+' else { return }',body[:250],filename)
 def test_router_proposes_without_creating_or_running(self):
  s=(ROOT/'JarvisEVO/Services/VerifiedLocalReadSession.swift').read_text()
  proposal=s[s.index('    func propose('):s.index('    func create(')]
  self.assertIn('core.route(text)',proposal)
  self.assertNotIn('persist(',proposal)
  self.assertNotIn('run()',proposal)
if __name__=='__main__':unittest.main()
