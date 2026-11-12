from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class CapabilityGateTests(unittest.TestCase):
 def test_independent_checks_retain_failures_without_packaging(self):
  text=(ROOT/'scripts/run_native_capabilities.sh').read_text()
  self.assertIn('BIOS_STATUS=',text);self.assertIn('FRAMEWORK_STATUS=',text);self.assertIn('VISION_STATUS=',text)
  self.assertIn('VisionRuntime/run_build.sh',text);self.assertIn('VisionProof/run_gate.sh',text)
  self.assertNotIn('build_ipa',text);self.assertNotIn('git push',text)
  self.assertIn('2496f9c14965c39589f53eea31bdb6d762b1d360',(ROOT/'Diagnostics/VisionRuntime/run_build.sh').read_text())
 def test_runtime_recipe_stays_single_mtmd_runtime(self):
  text=(ROOT/'Diagnostics/VisionRuntime/build-ios-mtmd.sh').read_text()
  self.assertEqual(text.count('libmtmd.a'),1)
  self.assertEqual(text.count('cmake --build '),2)
  self.assertEqual(text.count('--parallel 2'),2)
  self.assertIn('LLAMA_BUILD_TOOLS=ON',text)
 def test_diagnostic_project_not_main_target_sources(self):
  text=(ROOT/'project.yml').read_text()
  self.assertNotIn('Diagnostics',text)
  self.assertFalse(list((ROOT/'Diagnostics').rglob('*.gguf')))
  self.assertFalse(list((ROOT/'Diagnostics').rglob('*.iso')))
if __name__=='__main__':unittest.main()
