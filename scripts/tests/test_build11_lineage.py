from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class Build11LineageTests(unittest.TestCase):
 def test_preview_version_and_identity(self):
  s=(ROOT/'project.yml').read_text()
  self.assertIn('CURRENT_PROJECT_VERSION: 16',s) # Current preview; historical build-11 provenance stays pinned below.
  self.assertIn('MARKETING_VERSION: 0.1.1',s)
  self.assertIn('app.jarvisevo.ios',s)
 def test_provenance_keeps_archive_and_compiled_input_gates(self):
  s=(ROOT/'scripts/verify_build11_runtime_reuse.py').read_text()
  self.assertIn('5c5ca7fbfe812386fb6afb8bc20778c374e0f525',s)
  self.assertIn('assert changed<=allowed',s)
  self.assertIn('assert before==after,path',s)
  self.assertIn('assert digest==saved=="fcb5fb0ac432cd962461dfd7214caf8a40fdd438bea2ef5f31422879ddf341e8"',s)
  self.assertIn('before_project.replace("CURRENT_PROJECT_VERSION: 10","CURRENT_PROJECT_VERSION: 11",1)==after_project',s)
 def test_package_only_no_publication(self):
  s=(ROOT/'.github/workflows/build11-candidate.yml').read_text()
  self.assertIn('contents: read',s)
  self.assertIn('ci/backup-build11-20261115',s)
  self.assertIn('bash scripts/ci_combined_runtime.sh',s)
  self.assertIn('bash scripts/ci_package_only.sh',s)
  self.assertNotIn('gh release',s)
if __name__=='__main__':unittest.main()
