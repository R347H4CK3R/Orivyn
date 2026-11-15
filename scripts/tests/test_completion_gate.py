import importlib.util,pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('gate',ROOT/'scripts/verify_completion_gate.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
class CompletionGate(unittest.TestCase):
 def test_counts_fail_closed(self):
  good=dict(totalTestCount=31,passedTests=31,failedTests=0,skippedTests=0)
  gate.verify(good)
  for key in good:
   for bad in [None,True,-1,100,'31']:
    with self.assertRaises(ValueError):gate.verify(dict(good,**{key:bad}))
  with self.assertRaises(ValueError):gate.verify(dict(totalTestCount=0,passedTests=0,failedTests=0,skippedTests=0))
 def test_test_count_matches_sources_and_workflow_scope(self):
  names=['LocalCompletionContractTests','LocalAgentVersionRoutingTests','LocalCompletionGrammarTests','LocalCompletionReviewTests','LocalCompletionSessionTests']
  count=sum((ROOT/f'Tests/{n}.swift').read_text().count('func test') for n in names)
  self.assertEqual(count,31)
  script=(ROOT/'scripts/ci_completion_session.sh').read_text()
  for name in names:self.assertIn('-only-testing:JarvisEVOTests/'+name,script)
  self.assertNotIn('publish',script)
