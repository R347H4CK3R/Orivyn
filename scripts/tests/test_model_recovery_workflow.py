from pathlib import Path
import unittest
class RecoveryWorkflowTests(unittest.TestCase):
 def test_host_package_supports_existing_concurrency_apis(self):
  s=(Path(__file__).resolve().parents[2]/'.github/workflows/model-recovery.yml').read_text()
  self.assertIn('platforms:[.macOS(.v14)]',s)
  self.assertIn('python3 scripts/verify_recovery_tests.py artifacts/tests.log',s)
  self.assertIn('contents: read',s)
  self.assertNotIn('gh release',s)
if __name__=='__main__':unittest.main()
