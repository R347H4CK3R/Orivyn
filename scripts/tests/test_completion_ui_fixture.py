import importlib.util,json,pathlib,tempfile,unittest,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('seed',ROOT/'scripts/seed_completion_ui.py');seed=importlib.util.module_from_spec(spec);spec.loader.exec_module(seed)
class FixtureTests(unittest.TestCase):
 def test_seed_only_exact_test_root_and_validate_hash(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);c=p/'container';c.mkdir();s=p/'model.gguf';s.write_bytes(b'abc')
   m=dict(id='fixture',name='Fixture',fileName='model.gguf',byteCount=3,sha256=hashlib.sha256(b'abc').hexdigest(),license='test')
   target=seed.seed(c,s,m)
   self.assertEqual(target,c/'Library/Application Support/JarvisEVOUITests/Models')
   self.assertEqual(json.loads((target/'installed-models.json').read_text()),[m])
   with self.assertRaises(ValueError):seed.seed(c,s,m)
 def test_symlink_and_bad_digest_leave_no_manifest(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);c=p/'container';c.mkdir();s=p/'model';s.write_bytes(b'abc');outside=p/'outside';outside.mkdir();(c/'Library').symlink_to(outside,target_is_directory=True)
   m=dict(fileName='model.gguf',byteCount=3,sha256=hashlib.sha256(b'abc').hexdigest())
   with self.assertRaises(ValueError):seed.seed(c,s,m)
   self.assertEqual(list(outside.iterdir()),[])
 def test_bad_hash_and_escape_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);s=p/'model';s.write_bytes(b'abc');c=p/'container';c.mkdir()
   for name in ['model.gguf','../escape']:
    with self.assertRaises(ValueError):seed.seed(c,s,dict(fileName=name,byteCount=3,sha256='0'*64))
   self.assertFalse(list(c.rglob('installed-models.json')))

 def test_raw_symlink_paths_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);real=p/'real';real.mkdir();link=p/'link';link.symlink_to(real,target_is_directory=True)
   with self.assertRaises(ValueError):seed.safe_chain(link/'child')
