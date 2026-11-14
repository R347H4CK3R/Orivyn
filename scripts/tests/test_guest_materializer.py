import unittest,sys,tempfile,gzip,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import materialize_guest as m
class MaterializerTests(unittest.TestCase):
 def test_fixed_profile(self):
  self.assertEqual(m.DISK_BYTES,135266304);self.assertEqual(m.DISK_SHA,'78418639ecd90573da211b62a502334f569f029b913525f50601b09d928b244d')
 def test_rejects_corrupt_without_overwrite(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);(p/'bad.gz').write_bytes(gzip.compress(b'bad'));(p/'out.img').write_bytes(b'keep')
   with self.assertRaises(ValueError):m.materialize(p/'bad.gz',p/'out.img')
   self.assertEqual((p/'out.img').read_bytes(),b'keep')
 def test_rejects_symlink(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);(p/'x').write_bytes(b'x');(p/'link').symlink_to(p/'x')
   with self.assertRaises(ValueError):m.materialize(p/'link',p/'out')
if __name__=='__main__':unittest.main()
