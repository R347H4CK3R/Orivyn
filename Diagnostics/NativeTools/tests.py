import ctypes as C,json,pathlib,unittest,time,os
P=pathlib.Path(__file__).parent
L=C.CDLL(str(P/'libtestshim.so'));L.ov_create=L.ov_test_create;L.ov_destroy=L.ov_test_destroy;L.ov_validate=L.ov2_validate;L.ov_cancel=L.ov2_cancel;L.ov_free=L.ov2_free;L.ov_create.argtypes=[C.c_char_p,C.c_uint,C.c_uint,C.c_uint,C.POINTER(C.c_void_p)];L.ov_validate.argtypes=[C.c_void_p,C.c_char_p,C.c_size_t,C.c_int,C.POINTER(C.c_void_p)];L.ov_free.argtypes=[C.c_void_p];L.ov_destroy.argtypes=[C.c_void_p];L.ov_cancel.argtypes=[C.c_void_p]
MODEL=os.environ.get('TEST_MODEL',str(P/'model.gguf')).encode()
def call(name='get_app_info',args='{}'):return '<tool_call>\n{"name":"'+name+'","arguments":'+args+'}\n</tool_call>'
class Gate(unittest.TestCase):
 def setUp(self):self.h=C.c_void_p();self.assertEqual(L.ov_create(MODEL,3,2,60000,C.byref(self.h)),0)
 def tearDown(self):L.ov_destroy(self.h)
 def run_raw(self,s,eog=1):
  b=s.encode() if isinstance(s,str) else s;o=C.c_void_p();rc=L.ov_validate(self.h,b,len(b),eog,C.byref(o));v=json.loads(C.string_at(o)) if o.value else None;L.ov_free(o);return rc,v
 def test_valid_batch(self):
  rc,v=self.run_raw(call()+'\n'+call('list_models'));self.assertEqual(rc,0);self.assertEqual([x['name'] for x in v['reserved_reads']],['get_app_info','list_models'])
 def test_atomic_invalid_batch(self):
  self.assertNotEqual(self.run_raw(call()+'\n'+call('delete_all'))[0],0);self.assertEqual(self.run_raw(call())[0],0)
 def test_replay_rejected(self):self.assertEqual(self.run_raw(call())[0],0);self.assertNotEqual(self.run_raw(call())[0],0)
 def test_duplicate_batch(self):self.assertNotEqual(self.run_raw(call()+'\n'+call())[0],0)
 def test_truncated_close(self):self.assertNotEqual(self.run_raw(call()[:-5])[0],0)
 def test_extra_args(self):self.assertNotEqual(self.run_raw(call(args='{"unexpected":true}'))[0],0)
 def test_duplicate_key(self):self.assertNotEqual(self.run_raw('<tool_call>\n{"name":"get_app_info","arguments":{},"arguments":{}}\n</tool_call>')[0],0)
 def test_no_eog(self):self.assertNotEqual(self.run_raw(call(),0)[0],0)
 def test_no_plain_claim(self):self.assertNotEqual(self.run_raw('I uploaded everything.')[0],0)
 def test_cancel(self):L.ov_cancel(self.h);self.assertNotEqual(self.run_raw(call())[0],0)
 def test_size(self):self.assertNotEqual(self.run_raw(' '*65537)[0],0)
 def test_utf8(self):self.assertNotEqual(self.run_raw(b'\xff')[0],0)
 def test_embedded_null(self):self.assertNotEqual(self.run_raw(call()+'\x00')[0],0)
 def test_trailing_junk(self):self.assertNotEqual(self.run_raw(call()+' trailing')[0],0)
 def test_outside_plan(self):
  L.ov_destroy(self.h);self.assertEqual(L.ov_create(MODEL,1,1,60000,C.byref(self.h)),0);self.assertNotEqual(self.run_raw(call('list_models'))[0],0)
 def test_budget(self):
  L.ov_destroy(self.h);self.assertEqual(L.ov_create(MODEL,3,1,60000,C.byref(self.h)),0);self.assertNotEqual(self.run_raw(call()+'\n'+call('list_models'))[0],0)
 def test_sequential(self):self.assertEqual(self.run_raw(call())[0],0);self.assertEqual(self.run_raw(call('list_models'))[0],0)
 def test_expiry(self):
  L.ov_destroy(self.h);rc=L.ov_create(MODEL,3,2,1,C.byref(self.h));self.assertIn(rc,[0,1]);time.sleep(.02);self.assertNotEqual(self.run_raw(call())[0],0)
 def test_invalid_utf8_in_name(self):self.assertNotEqual(self.run_raw(b'<tool_call>\n{"name":"get_app_\xffinfo","arguments":{}}\n</tool_call>')[0],0)
 def test_escaped_duplicate(self):self.assertNotEqual(self.run_raw('<tool_call>\n{"name":"get_app_info","arguments":{},"argum\\u0065nts":{}}\n</tool_call>')[0],0)
 def test_nested_excessive(self):self.assertNotEqual(self.run_raw(call(args='{"a":'+('['*10)+'0'+(']'*10)+'}'))[0],0)
 def test_concurrent_replay(self):
  from concurrent.futures import ThreadPoolExecutor
  with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(lambda _:self.run_raw(call())[0],range(2)))
  self.assertEqual(sorted(results),[0,1])
 def test_owner_survives(self):
  L.ov_test_owner_survives.argtypes=[C.c_char_p];self.assertEqual(L.ov_test_owner_survives(MODEL),0)
 @unittest.skipUnless(os.environ.get("MISMATCHED_MODEL"), "set MISMATCHED_MODEL for a different-template GGUF")
 def test_mismatched_template_rejected(self):
  h=C.c_void_p();self.assertNotEqual(L.ov_create(os.environ['MISMATCHED_MODEL'].encode(),3,2,60000,C.byref(h)),0);self.assertFalse(h.value)
if __name__=='__main__':unittest.main(verbosity=2)
