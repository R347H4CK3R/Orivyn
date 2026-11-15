"""Fast guard tests; load only pure diagnostic helpers, never start evaluation."""
import ast,pathlib,unittest,uuid,subprocess
from unittest.mock import patch
source=pathlib.Path(__file__).with_name('evaluate_generic.py').read_text()
ns={'uuid':uuid}
for node in ast.parse(source).body:
 if isinstance(node,ast.FunctionDef) and node.name in ('requested_read','exact_no_match'):
  exec(compile(ast.Module(body=[node],type_ignores=[]),'generic-oracles','exec'),ns)
class Oracles(unittest.TestCase):
 def test_summary_and_final_status_share_score_key(self):
  tree=ast.parse(source)
  summary=next(n for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='summary' for t in n.targets))
  final=tree.body[-1]
  for passes in [5,6]:
   rows=[dict(mode='baseline',passed=False) for _ in range(6)]+[dict(mode='native',passed=i<passes) for i in range(6)]
   local={'subprocess':subprocess,'sha':'fixture','results':rows}
   with patch.object(subprocess,'check_output',return_value='fixture'):
    exec(compile(ast.Module(body=[summary],type_ignores=[]),'summary','exec'),local)
   self.assertEqual(local['summary']['nativePassed'],passes)
   if passes==6:exec(compile(ast.Module(body=[final],type_ignores=[]),'status','exec'),local)
   else:
    with self.assertRaises(SystemExit) as stopped:exec(compile(ast.Module(body=[final],type_ignores=[]),'status','exec'),local)
    self.assertEqual(stopped.exception.code,1)
 def test_uuid_case_preserves_identity(self):
  cid='abcdef12-1234-5678-9012-abcdef123456'
  for spelling in [cid,cid.upper()]:
   self.assertTrue(ns['requested_read'](dict(id=spelling,messageIndex=2,offset=0),cid,2))
 def test_wrong_scope_and_malformed_identity_rejected(self):
  cid='abcdef12-1234-5678-9012-abcdef123456';base=dict(id=cid,messageIndex=2,offset=0)
  cases=[dict(base,id='not-id'),dict(base,id=cid.replace('-','')),dict(base,id='00000000-0000-0000-0000-000000000000'),
   dict(base,messageIndex=3),dict(base,offset=1),dict(base,messageIndex=True),dict(base,extra=1)]
  for value in cases:
   with self.subTest(value=value):self.assertFalse(ns['requested_read'](value,cid,2))
 def test_no_match_cannot_pass_by_negation_substring(self):
  self.assertTrue(ns['exact_no_match']('No matching conversation was found.'))
  for answer in ['No matching conversation was found. However, here is a match.','There is none, but I found Sequoia.','No match: ID12345','']:
   with self.subTest(answer=answer):self.assertFalse(ns['exact_no_match'](answer))
if __name__=='__main__':unittest.main()
