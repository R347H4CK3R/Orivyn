import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class ChatLocalTaskBridgeTests(unittest.TestCase):
 def test_composer_has_review_only_bridge(self):
  text=(ROOT/'JarvisEVO/UI/RootView.swift').read_text()
  self.assertIn('LocalAgentView(model: model, initialGoal: request.goal, initialChecklist: request.proposedChecklist)',text)
  self.assertIn('composer.localTask.review',text)
  self.assertIn('hasAttachments: !model.pendingAttachments.isEmpty',text)
 def test_seed_does_not_run(self):
  text=(ROOT/'JarvisEVO/UI/LocalAgentView.swift').read_text()
  self.assertIn('_goal = State(initialValue: initialGoal)',text)
  setup=text.split('.task {',1)[1].split('.onDisappear',1)[0]
  self.assertNotIn('.run()',setup)
if __name__=='__main__': unittest.main()
