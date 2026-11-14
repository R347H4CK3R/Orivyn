from pathlib import Path
import importlib.util,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
class FoundationHarnessTests(unittest.TestCase):
 def test_harness_copies_exact_production_sources_without_ios_target(self):
  script=ROOT/'scripts/run_foundation_tests.py'
  self.assertTrue(script.exists(),'Foundation-only execution harness missing')
  spec=importlib.util.spec_from_file_location('harness',script);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  with tempfile.TemporaryDirectory() as directory:
   output=Path(directory)/'proof';module.prepare(ROOT,output)
   for name in module.SOURCES:
    self.assertEqual((output/'Sources/JarvisEVO'/Path(name).name).read_bytes(),(ROOT/name).read_bytes())
   self.assertIn('JarvisEVO', (output/'Package.swift').read_text())
   self.assertNotIn('iOS', (output/'Package.swift').read_text())
 def test_existing_output_is_not_overwritten(self):
  script=ROOT/'scripts/run_foundation_tests.py';self.assertTrue(script.exists(),'Foundation-only execution harness missing')
  spec=importlib.util.spec_from_file_location('harness',script);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  with tempfile.TemporaryDirectory() as directory:
   with self.assertRaises(FileExistsError):module.prepare(ROOT,Path(directory))
if __name__=='__main__':unittest.main()
