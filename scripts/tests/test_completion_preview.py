"""Release composition contracts, not native execution evidence."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class CompletionPreviewTests(unittest.TestCase):
 def test_scoped_gates_precede_package(self):
  s=(ROOT/'.github/workflows/completion-build15.yml').read_text()
  required=['python3 scripts/verify_recovery_tests.py artifacts/tests.log','bash scripts/ci_combined_runtime.sh',"-p 'test_completion*.py'",'node --test scripts/agent-tests/*.test.cjs','bash scripts/ci_completion_acceptance.sh','bash scripts/ci_package_only.sh']
  positions=[s.index(x) for x in required]
  self.assertEqual(positions,sorted(positions))
  self.assertIn('XCODE=/Applications/Xcode_26.1.app',s)
  self.assertIn('ci/completion-build15-20261115',s)
  self.assertIn('contents: read',s)
  self.assertIn('Orivyn-build15-package-evidence',s)
  self.assertNotIn('gh release',s)
 def test_candidate_identity_and_limits(self):
  s=(ROOT/'project.yml').read_text()
  for x in ['CURRENT_PROJECT_VERSION: 17','MARKETING_VERSION: 0.1.1','app.jarvisevo.ios']:self.assertIn(x,s)
  doc=(ROOT/'docs/BUILD15_CANDIDATE.md').read_text()
  for x in ['not completed 1.0.0','programmatic review/approval','physical','Generic']:
   self.assertIn(x,doc)
if __name__=='__main__':unittest.main()
