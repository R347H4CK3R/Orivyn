import importlib.util,json,pathlib,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('v',ROOT/'scripts/verify_completion_ui_state.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
class StateTests(unittest.TestCase):
 def test_empty_changed_and_executed_states_fail(self):
  good=dict(version=3,approvalRevision=0,status='ready',steps=0,history=[],pending=None,answer=None,id='12345678-1234-1234-1234-123456789ABC',revision=0,error=None,goal='Inspect app and Cedar acceptance memory',completionContract=dict(schema=1,steps=[dict(name='get_app_info',arguments={}),dict(name='search_memory',arguments=dict(query='Cedar acceptance final',limit=3))]))
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);f=p/'12345678-1234-1234-1234-123456789ABC.json'
   with self.assertRaises(ValueError):v.verify(p)
   f.write_text(json.dumps(good));self.assertEqual(v.verify(p),good)
   for key,value in [('id','b'),('history',[{}]),('answer','premature'),('steps',1)]:
    f.write_text(json.dumps(dict(good,**{key:value})))
    with self.assertRaises(ValueError):v.verify(p,good)

   for key in ['pending','answer','error']:
    bad=dict(good);bad.pop(key);f.write_text(json.dumps(bad))
    with self.assertRaises(ValueError):v.verify(p)
   for key in ['approvalRevision','steps','revision']:
    f.write_text(json.dumps(dict(good,**{key:False})))
    with self.assertRaises(ValueError):v.verify(p)
   f.write_text(json.dumps(dict(good,id='bad')))
   with self.assertRaises(ValueError):v.verify(p)

   bad=json.loads(json.dumps(good));bad['completionContract']['schema']=True;f.write_text(json.dumps(bad))
   with self.assertRaises(ValueError):v.verify(p)
