import unittest,pathlib,subprocess
import prepare_build
class RecipeTests(unittest.TestCase):
 def test_exact_upstream_script_required(self):
  with self.assertRaises(ValueError): prepare_build.transform('unexpected upstream')
 def test_two_ios_builds_only_and_single_runtime(self):
  s=prepare_build.transform(pathlib.Path('source/build-xcframework.sh').read_text())
  self.assertEqual(s.count('cmake --build '),2)
  self.assertEqual(s.count('--target mtmd --parallel 2'),2)
  self.assertIn('LLAMA_BUILD_TOOLS=ON',s)
  self.assertIn('libmtmd.a',s)
  self.assertIn('header "mtmd.h"',s)
  self.assertIn('header "mtmd-helper.h"',s)
  self.assertNotIn('cmake -B build-macos',s)
  self.assertEqual(s.count('xcrun xcodebuild -create-xcframework'),1)
 def test_generated_shell_parses(self):
  s=prepare_build.transform(pathlib.Path('source/build-xcframework.sh').read_text())
  self.assertEqual(subprocess.run(['bash','-n'],input=s,text=True).returncode,0)
