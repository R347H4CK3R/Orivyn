from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class SnapshotPreviewTests(unittest.TestCase):
 def test_numbered_snapshot_gate_is_identical_to_verified_gate(self):
  old=(ROOT/'.github/workflows/snapshot-lifetime.yml').read_text()
  expected=old.replace('Verify native snapshot lifetime without simulator boot','Verify Orivyn build 12 snapshot preview').replace('ci/snapshot-lifetime-sdk-20261115','ci/snapshot-build12-20261115').replace("['.github/workflows/snapshot-lifetime.yml']","['.github/workflows/snapshot-build12.yml']").replace('group: snapshot-lifetime','group: snapshot-build12').replace('Orivyn-snapshot-lifetime-evidence','Orivyn-build12-package-evidence')
  actual=(ROOT/'.github/workflows/snapshot-build12.yml').read_text()
  self.assertEqual(expected,actual)
  self.assertNotIn('gh release',actual)
 def test_identity_and_unique_build(self):
  p=(ROOT/'project.yml').read_text()
  for value in ('CURRENT_PROJECT_VERSION: 15','MARKETING_VERSION: 0.1.1','app.jarvisevo.ios'):
   self.assertIn(value,p)
if __name__=='__main__': unittest.main()
