import importlib.util,pathlib,unittest
p=pathlib.Path(__file__).resolve().parents[1]/'verify_recovery_tests.py'
spec=importlib.util.spec_from_file_location('verify_recovery_tests',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ResultsTests(unittest.TestCase):
 def sample(self): return ''.join(f"Test Case 'testFailedFirstInstall{i}' passed (0.001 seconds).\n" for i in range(19))+'Executed 19 tests, with 0 failures\n'
 def test_failure_word_in_name_is_not_failed_case(self): m.verify(self.sample())
 def test_failure_and_skip_results_rejected_despite_good_summary(self):
  for result in ['failed','skipped']:
   with self.assertRaises(ValueError): m.verify(self.sample().replace(' passed (',f' {result} (',1))
 def test_summary_only_zero_tests_and_extra_cases_rejected(self):
  for text in ['Executed 19 tests, with 0 failures',self.sample()+"Test Case 'extra' passed (0.001 seconds).\n",self.sample().replace("Test Case 'testFailedFirstInstall0' passed (0.001 seconds).\n",'')]:
   with self.assertRaises(ValueError): m.verify(text)
 def test_missing_summary_rejected(self):
  with self.assertRaises(ValueError): m.verify(self.sample().split('Executed')[0])
if __name__=='__main__':unittest.main()
