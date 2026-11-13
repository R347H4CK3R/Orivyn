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
 def test_grammar_is_explicit_resource_and_agent_tests_are_gated(self):
  project=(ROOT/'project.yml').read_text()
  self.assertIn('- path: JarvisEVO/Resources/LocalAgentDecision.gbnf\n        buildPhase: resources',project)
  for name in ['ci_macos.sh','run_virtual_desktop_gate.sh']:
   self.assertIn('node --test scripts/agent-tests/*.test.cjs',(ROOT/'scripts'/name).read_text())
  self.assertIn('-only-testing:JarvisEVOTests/LocalAgentCoreTests',(ROOT/'scripts/run_virtual_desktop_gate.sh').read_text())
 def test_verified_mode_does_not_invoke_inference_and_persists_before_read(self):
  s=(ROOT/'JarvisEVO/Services/VerifiedLocalReadSession.swift').read_text()
  self.assertNotIn('GenerationRequest',s)
  self.assertNotIn('provider.stream',s)
  self.assertLess(s.index('try persist(next)'),s.index('try LocalReadTools.execute('))
  self.assertIn('model.beginVerifiedReads',s)
  self.assertIn('model.endVerifiedReads',s)
 def test_router_proposes_without_creating_or_running(self):
  s=(ROOT/'JarvisEVO/Services/VerifiedLocalReadSession.swift').read_text()
  proposal=s[s.index('    func propose('):s.index('    func create(')]
  self.assertIn('core.route(text)',proposal)
  self.assertNotIn('persist(',proposal)
  self.assertNotIn('run()',proposal)
if __name__=='__main__':unittest.main()
