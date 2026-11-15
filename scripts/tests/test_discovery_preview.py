from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class DiscoveryPreviewTests(unittest.TestCase):
 def test_gate_retains_exact_host_and_package_checks(self):
  source=(ROOT/'.github/workflows/recovery-build13.yml').read_text().replace('build 13 recovery','build 14 reviewed-task').replace('recovery-build13','discovery-build14').replace('Orivyn-build13-package-evidence','Orivyn-build14-package-evidence')
  source=source.replace("          python3 -m unittest discover -s scripts/tests -p 'test_generate_project.py'","          python3 -m unittest discover -s scripts/tests -p 'test_generate_project.py'\n          python3 -m unittest discover -s scripts/tests -p 'test_reviewed*.py'")
  self.assertEqual((ROOT/'.github/workflows/discovery-build14.yml').read_text(),source)
